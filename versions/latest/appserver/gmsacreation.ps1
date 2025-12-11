#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Creates gMSA infrastructure for IIS applications on ad.geha.home domain
.DESCRIPTION
    This script:
    1. Verifies KDS Root Key exists (required for gMSA)
    2. Creates necessary OUs for gMSA accounts and groups
    3. Creates a security group to control gMSA access
    4. Creates the gMSA service account
    5. Adds specified computer accounts to the security group
#>

Import-Module ActiveDirectory

# ==================== CONFIGURATION ====================
$DomainDN = "DC=ad,DC=geha,DC=home"
$DNSDomain = "ad.geha.home"

# OU Configuration
$BaseOUName = "ServiceAccounts"
$BaseOUPath = $DomainDN
$gMSAGroupsOUName = "gMSA-Groups"
$gMSAAccountsOUName = "gMSA-Accounts"

# Group Configuration
$GroupName = "gr-bim-on-prem"
$GroupDescription = "gMSA group for IIS applications on W11-PROD-1"

# gMSA Configuration
$gMSAName = "blue-test-01-bh"
$gMSADescription = "gMSA service account for IIS on W11-PROD-1"
$PasswordIntervalDays = 30

# Computer accounts that will use this gMSA
$VMList = @('prm-expggprm-01$')  # Note: Computer accounts must end with $

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

# ==================== MAIN SCRIPT ====================

Write-Status "Starting gMSA setup for ad.geha.home domain..." "INFO"
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

# --- Step 3: Create Security Group ---
Write-Status "`nStep 3: Creating security group..." "INFO"

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
    } else {
        Write-Status "Group already exists: $GroupName" "SUCCESS"
    }
} catch {
    Write-Status "Failed to create group: $_" "ERROR"
    exit 1
}

# --- Step 4: Create or Update gMSA ---
Write-Status "`nStep 4: Creating gMSA account..." "INFO"

$gMSASamAccountName = $gMSAName + '$'
try {
    $existingGMSA = Get-ADServiceAccount -Filter "SamAccountName -eq '$gMSASamAccountName'" -ErrorAction SilentlyContinue
   
    if ($existingGMSA) {
        Write-Status "gMSA already exists. Updating configuration..." "WARNING"
        Set-ADServiceAccount -Identity $gMSAName `
            -Description $gMSADescription `
            -DNSHostName "$gMSAName.$DNSDomain" `
            -PrincipalsAllowedToRetrieveManagedPassword $GroupName `
            -Enabled $true `
            -ErrorAction Stop
        Write-Status "Updated gMSA: $gMSAName" "SUCCESS"
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
    }
} catch {
    Write-Status "Failed to create/update gMSA: $_" "ERROR"
    exit 1
}

# --- Step 5: Add Computer Accounts to Group ---
Write-Status "`nStep 5: Adding computer accounts to security group..." "INFO"

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
        } else {
            Write-Status "$computerAccount is already a member of $GroupName" "SUCCESS"
        }
    } catch {
        Write-Status "Failed to add $computerAccount to group: $_" "ERROR"
    }
}

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
Write-Host "  Security Group:" -ForegroundColor Yellow
Write-Host "    - Name: $GroupName"
Write-Host "    - Location: $gMSAGroupsOUDN"
Write-Host ""
Write-Host "  gMSA Account:" -ForegroundColor Yellow
Write-Host "    - Name: $gMSAName"
Write-Host "    - DNS Name: $gMSAName.$DNSDomain"
Write-Host "    - Location: $gMSAAccountsOUDN"
Write-Host "    - Password Rotation: Every $PasswordIntervalDays days"
Write-Host ""
Write-Host "Next Steps on W11-PROD-1:" -ForegroundColor Green
Write-Host "  1. Join W11-PROD-1 to the domain (if not already done)"
Write-Host "  2. Reboot W11-PROD-1"
Write-Host "  3. Run on W11-PROD-1 as Administrator:"
Write-Host "     Install-ADServiceAccount -Identity $gMSAName" -ForegroundColor Cyan
Write-Host "  4. Test the installation:"
Write-Host "     Test-ADServiceAccount -Identity $gMSAName" -ForegroundColor Cyan
Write-Host "  5. In IIS, set Application Pool identity to:"
Write-Host "     AD.GEHA.HOME\$gMSAName$" -ForegroundColor Cyan
Write-Host "     (Leave password blank - it's managed automatically)"
Write-Host ""
