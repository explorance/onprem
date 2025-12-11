#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates gMSA infrastructure for IIS applications on ad.geha.home domain
.PRE-REQU****
    	-Get-KdsRootKey
	-Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))
.DESCRIPTION
    This script:
    1. Verifies KDS Root Key exists (required for gMSA)
    2. Creates necessary OUs for gMSA accounts and groups
    3. Creates a security group to control gMSA access
    4. Creates the gMSA service account
    5. Adds specified computer accounts to the security group
.PARAMETER ConfigPath
    Path to JSON configuration file. Defaults to gMSA-creation-config.json in script directory.
.EXAMPLE
    .\GMSA-CREATION.ps1
    Uses default configuration file (gMSA-creation-config.json in script directory)
.EXAMPLE
    .\GMSA-CREATION.ps1 -ConfigPath "C:\Config\production-gmsa.json"
    Uses specified configuration file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Path to JSON configuration file")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Configuration file not found: $_"
        }
        if ($_ -notmatch '\.json$') {
            throw "Configuration file must be a JSON file"
        }
        return $true
    })]
    [string]$ConfigPath = "$PSScriptRoot\gmsa-creation-config.json"
)

Import-Module ActiveDirectory

# ==================== FUNCTIONS ====================

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

function Test-ADObjectExists {
    param(
        [string]$Identity,
        [string]$ObjectClass
    )
    try {
        $null = Get-ADObject -Identity $Identity -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-ConfigurationFile {
    param(
        [string]$ConfigPath
    )

    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

        # Validate required top-level properties
        $requiredProps = @('domain', 'organizationalUnits', 'computerAccounts', 'gmsaAccounts')
        foreach ($prop in $requiredProps) {
            if (-not $config.PSObject.Properties.Name.Contains($prop)) {
                throw "Missing required property: $prop"
            }
        }

        # Validate domain configuration
        if (-not $config.domain.domainDN -or -not $config.domain.dnsDomain) {
            throw "Domain configuration incomplete. Requires domainDN and dnsDomain"
        }

        # Validate OU configuration
        $requiredOUProps = @('baseOUName', 'baseOUPath', 'gMSAGroupsOUName', 'gMSAAccountsOUName')
        foreach ($prop in $requiredOUProps) {
            if (-not $config.organizationalUnits.PSObject.Properties.Name.Contains($prop)) {
                throw "Missing OU configuration property: $prop"
            }
        }

        # Validate computer accounts array
        if ($config.computerAccounts -isnot [System.Array]) {
            throw "computerAccounts must be an array"
        }

        # Auto-correct computer accounts missing $ suffix
        for ($i = 0; $i -lt $config.computerAccounts.Count; $i++) {
            if ($config.computerAccounts[$i] -notmatch '\$$') {
                Write-Status "Computer account '$($config.computerAccounts[$i])' should end with $ - auto-correcting" "WARNING"
                $config.computerAccounts[$i] = "$($config.computerAccounts[$i])$"
            }
        }

        # Validate each gMSA account configuration
        if ($config.gmsaAccounts -isnot [System.Array] -or $config.gmsaAccounts.Count -eq 0) {
            throw "gmsaAccounts must be a non-empty array"
        }

        $groupNames = @()
        foreach ($gmsa in $config.gmsaAccounts) {
            if (-not $gmsa.name) {
                throw "gMSA account missing required 'name' property"
            }
            if (-not $gmsa.description) {
                throw "gMSA account '$($gmsa.name)' missing required 'description' property"
            }
            if (-not $gmsa.securityGroup) {
                throw "gMSA account '$($gmsa.name)' missing required 'securityGroup' property"
            }
            if (-not $gmsa.securityGroup.description) {
                throw "gMSA account '$($gmsa.name)' security group missing 'description' property"
            }
            if (-not $gmsa.passwordIntervalDays -or $gmsa.passwordIntervalDays -lt 1) {
                throw "gMSA account '$($gmsa.name)' has invalid passwordIntervalDays (must be >= 1)"
            }

            # Auto-generate security group name if not provided
            if (-not $gmsa.securityGroup.name) {
                $gmsa.securityGroup.name = "gr-$($gmsa.name)"
                Write-Status "Auto-generated security group name for '$($gmsa.name)': gr-$($gmsa.name)" "INFO"
            }

            $groupNames += $gmsa.securityGroup.name
        }

        # Check for duplicate security group names
        $duplicates = $groupNames | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($duplicates) {
            throw "Duplicate security group names detected: $($duplicates.Name -join ', ')"
        }

        Write-Status "Configuration file validated successfully" "SUCCESS"
        return $config

    } catch {
        Write-Status "Configuration validation failed: $_" "ERROR"
        exit 1
    }
}

# ==================== MAIN SCRIPT ====================

Write-Status "Starting gMSA setup script..." "INFO"

# Load and validate configuration
Write-Status "Loading configuration from: $ConfigPath" "INFO"
$config = Test-ConfigurationFile -ConfigPath $ConfigPath

# Extract configuration values
$DomainDN = $config.domain.domainDN
$DNSDomain = $config.domain.dnsDomain
$BaseOUName = $config.organizationalUnits.baseOUName
$BaseOUPath = $config.organizationalUnits.baseOUPath
$gMSAGroupsOUName = $config.organizationalUnits.gMSAGroupsOUName
$gMSAAccountsOUName = $config.organizationalUnits.gMSAAccountsOUName
$VMList = $config.computerAccounts
$gMSAAccounts = $config.gmsaAccounts

Write-Status "Configuration loaded: $($gMSAAccounts.Count) gMSA account(s) to process" "INFO"
Write-Status "This script will create OUs, groups, and gMSA accounts" "INFO"
Write-Host ""

# --- Step 1: Verify KDS Root Key ---
Write-Status "Step 1: Checking KDS Root Key (required for gMSA)..." "INFO"

$kdsRootKey = Get-KdsRootKey
if (-not $kdsRootKey) {
    Write-Status "KDS Root Key not found. Creating it now..." "WARNING"
    Write-Status "Note: In production, key takes 10 hours to replicate. Using -EffectiveTime for immediate use." "WARNING"
    
    try {
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) -ErrorAction Stop
        Write-Status "KDS Root Key created successfully" "SUCCESS"
    } catch {
        Write-Status "Failed to create KDS Root Key: $_" "ERROR"
        exit 1
    }
} else {
    Write-Status "KDS Root Key already exists" "SUCCESS"
}

# --- Step 2: Create OU Structure ---
Write-Status "`nStep 2: Creating OU structure..." "INFO"

# Create base ServiceAccounts OU
$baseOUDN = "OU=$BaseOUName,$BaseOUPath"
if (-not (Test-ADObjectExists -Identity $baseOUDN -ObjectClass "organizationalUnit")) {
    try {
        New-ADOrganizationalUnit -Name $BaseOUName -Path $BaseOUPath -Description "Container for service accounts and groups" -ErrorAction Stop
        Write-Status "Created OU: $BaseOUName" "SUCCESS"
    } catch {
        Write-Status "Failed to create base OU: $_" "ERROR"
        exit 1
    }
} else {
    Write-Status "Base OU already exists: $BaseOUName" "SUCCESS"
}

# Create gMSA Groups OU
$gMSAGroupsOUDN = "OU=$gMSAGroupsOUName,$baseOUDN"
if (-not (Test-ADObjectExists -Identity $gMSAGroupsOUDN -ObjectClass "organizationalUnit")) {
    try {
        New-ADOrganizationalUnit -Name $gMSAGroupsOUName -Path $baseOUDN -Description "Groups for gMSA authorization" -ErrorAction Stop
        Write-Status "Created OU: $gMSAGroupsOUName" "SUCCESS"
    } catch {
        Write-Status "Failed to create gMSA Groups OU: $_" "ERROR"
        exit 1
    }
} else {
    Write-Status "gMSA Groups OU already exists" "SUCCESS"
}

# Create gMSA Accounts OU
$gMSAAccountsOUDN = "OU=$gMSAAccountsOUName,$baseOUDN"
if (-not (Test-ADObjectExists -Identity $gMSAAccountsOUDN -ObjectClass "organizationalUnit")) {
    try {
        New-ADOrganizationalUnit -Name $gMSAAccountsOUName -Path $baseOUDN -Description "gMSA service accounts" -ErrorAction Stop
        Write-Status "Created OU: $gMSAAccountsOUName" "SUCCESS"
    } catch {
        Write-Status "Failed to create gMSA Accounts OU: $_" "ERROR"
        exit 1
    }
} else {
    Write-Status "gMSA Accounts OU already exists" "SUCCESS"
}

# --- Step 3: Create Security Groups ---
Write-Status "`nStep 3: Creating security groups for each gMSA..." "INFO"

$createdGroups = @()
foreach ($gmsa in $gMSAAccounts) {
    $GroupName = $gmsa.securityGroup.name
    $GroupDescription = $gmsa.securityGroup.description

    try {
        if (-not (Get-ADGroup -Filter "SamAccountName -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $GroupName `
                -SamAccountName $GroupName `
                -GroupCategory Security `
                -GroupScope Global `
                -DisplayName $GroupName `
                -Path $gMSAGroupsOUDN `
                -Description $GroupDescription `
                -ErrorAction Stop
            Write-Status "Created group: $GroupName" "SUCCESS"
            $createdGroups += $GroupName
        } else {
            Write-Status "Group already exists: $GroupName" "SUCCESS"
            $createdGroups += $GroupName
        }
    } catch {
        Write-Status "Failed to create group $GroupName : $_" "ERROR"
        exit 1
    }
}

Write-Status "Processed $($createdGroups.Count) security group(s)" "INFO"

# --- Step 4: Create or Update gMSA Accounts ---
Write-Status "`nStep 4: Creating gMSA accounts..." "INFO"

$createdGMSAs = @()
foreach ($gmsa in $gMSAAccounts) {
    $gMSAName = $gmsa.name
    $gMSADescription = $gmsa.description
    $GroupName = $gmsa.securityGroup.name
    $PasswordIntervalDays = $gmsa.passwordIntervalDays

    $gMSASamAccountName = $gMSAName + '$'

    try {
        $existingGMSA = Get-ADServiceAccount -Filter "SamAccountName -eq '$gMSASamAccountName'" -ErrorAction SilentlyContinue

        if ($existingGMSA) {
            Write-Status "gMSA '$gMSAName' already exists. Updating configuration..." "WARNING"
            Set-ADServiceAccount -Identity $gMSAName `
                -Description $gMSADescription `
                -DNSHostName "$gMSAName.$DNSDomain" `
                -PrincipalsAllowedToRetrieveManagedPassword $GroupName `
                -Enabled $true `
                -ErrorAction Stop
            Write-Status "Updated gMSA: $gMSAName" "SUCCESS"
            $createdGMSAs += $gMSAName
        } else {
            New-ADServiceAccount -Name $gMSAName `
                -Description $gMSADescription `
                -DNSHostName "$gMSAName.$DNSDomain" `
                -ManagedPasswordIntervalInDays $PasswordIntervalDays `
                -Path $gMSAAccountsOUDN `
                -PrincipalsAllowedToRetrieveManagedPassword $GroupName `
                -Enabled $true `
                -ErrorAction Stop
            Write-Status "Created gMSA: $gMSAName" "SUCCESS"
            $createdGMSAs += $gMSAName
        }
    } catch {
        Write-Status "Failed to create/update gMSA '$gMSAName': $_" "ERROR"
        exit 1
    }
}

Write-Status "Processed $($createdGMSAs.Count) gMSA account(s)" "INFO"

# --- Step 5: Add Computer Accounts to All Security Groups ---
Write-Status "`nStep 5: Adding computer accounts to security groups..." "INFO"
Write-Status "Note: All computers will be added to ALL gMSA security groups" "INFO"

$membershipCount = 0
foreach ($gmsa in $gMSAAccounts) {
    $GroupName = $gmsa.securityGroup.name
    Write-Status "Processing group: $GroupName" "INFO"

    foreach ($computerAccount in $VMList) {
        try {
            # Verify computer exists in AD
            $computer = Get-ADComputer -Filter "SamAccountName -eq '$computerAccount'" -ErrorAction SilentlyContinue

            if (-not $computer) {
                Write-Status "Computer $computerAccount not found in AD. Skipping..." "WARNING"
                Write-Status "Make sure the computer is domain-joined first!" "WARNING"
                continue
            }

            # Check if already a member
            $isMember = Get-ADGroupMember -Identity $GroupName -ErrorAction SilentlyContinue |
                        Where-Object {$_.SamAccountName -eq $computerAccount}

            if (-not $isMember) {
                Add-ADGroupMember -Identity $GroupName -Members $computerAccount -ErrorAction Stop
                Write-Status "Added $computerAccount to group $GroupName" "SUCCESS"
                $membershipCount++
            } else {
                Write-Status "$computerAccount is already a member of $GroupName" "SUCCESS"
            }
        } catch {
            Write-Status "Failed to add $computerAccount to group $GroupName : $_" "ERROR"
        }
    }
}

Write-Status "Processed computer membership: $membershipCount new membership(s) added" "INFO"

# --- Summary ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Status "gMSA Setup Complete!" "SUCCESS"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created/Verified Resources:" -ForegroundColor White
Write-Host "  OU Structure:" -ForegroundColor Yellow
Write-Host "    - $baseOUDN"
Write-Host "    - $gMSAGroupsOUDN"
Write-Host "    - $gMSAAccountsOUDN"
Write-Host ""

Write-Host "  gMSA Accounts and Security Groups:" -ForegroundColor Yellow
foreach ($gmsa in $gMSAAccounts) {
    Write-Host "    [$($gmsa.name)]" -ForegroundColor Cyan
    Write-Host "      - gMSA DNS Name: $($gmsa.name).$DNSDomain"
    Write-Host "      - Security Group: $($gmsa.securityGroup.name)"
    Write-Host "      - Password Rotation: Every $($gmsa.passwordIntervalDays) days"
    Write-Host "      - Description: $($gmsa.description)"
    Write-Host ""
}

Write-Host "  Authorized Computer Accounts:" -ForegroundColor Yellow
foreach ($computer in $VMList) {
    Write-Host "    - $computer (member of ALL gMSA groups)"
}
Write-Host ""

Write-Host "Next Steps on Target Computers:" -ForegroundColor Green
Write-Host "  For each computer listed above, run as Administrator:" -ForegroundColor White
foreach ($gmsa in $gMSAAccounts) {
    Write-Host "    1. Install-ADServiceAccount -Identity $($gmsa.name)" -ForegroundColor Cyan
    Write-Host "    2. Test-ADServiceAccount -Identity $($gmsa.name)" -ForegroundColor Cyan
    Write-Host "    3. In IIS, set Application Pool identity to: $DNSDomain\$($gmsa.name)$" -ForegroundColor Cyan
    Write-Host "       (Leave password blank - it's managed automatically)"
    Write-Host ""
}