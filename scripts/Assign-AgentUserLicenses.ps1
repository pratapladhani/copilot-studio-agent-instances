<#
.SYNOPSIS
Assigns licenses to an Agent User.

.DESCRIPTION
This script assigns the required licenses (Teams, Outlook, Microsoft 365, Copilot Studio) 
to an Agent User so they can operate within the Microsoft 365 ecosystem.

.PARAMETER ConfigFile
Path to a JSON configuration file containing AgentUserId and TenantId.

.PARAMETER TenantId
The Tenant ID (required if not using ConfigFile).

.PARAMETER AgentUserId
The Agent User's Object ID (required if not using ConfigFile).

.EXAMPLE
.\Assign-AgentUserLicenses.ps1 -ConfigFile ".\budget-advisor-user-config.json"

.EXAMPLE
.\Assign-AgentUserLicenses.ps1 -TenantId "your-tenant-id" -AgentUserId "user-object-id"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$AgentUserId
)

# Display script header
Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host "                           Agent User License Assignment Script                                 " -ForegroundColor Cyan
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Reading configuration from file: $ConfigFile" -ForegroundColor Blue
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        $TenantId = $config.TenantId
        $AgentUserId = $config.AgentUserId
        
        if (-not $AgentUserId) {
            Write-Host "ERROR: AgentUserId not found in config file. Run createAgenticUser.ps1 first." -ForegroundColor Red
            exit 1
        }
        
        Write-Host "  • Tenant ID: $TenantId" -ForegroundColor Gray
        Write-Host "  • Agent User ID: $AgentUserId" -ForegroundColor Gray
    }
    catch {
        Write-Host "ERROR: Failed to read configuration file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
elseif (-not $TenantId -or -not $AgentUserId) {
    Write-Host "ERROR: Either provide -ConfigFile or both -TenantId and -AgentUserId" -ForegroundColor Red
    exit 1
}

# Connect to Microsoft Graph
Write-Host ""
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -TenantId $TenantId -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" -NoWelcome
    Write-Host "Connected successfully!" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get available licenses in the tenant
Write-Host ""
Write-Host "Fetching available licenses in tenant..." -ForegroundColor Yellow
try {
    $subscribedSkus = Get-MgSubscribedSku -All
    Write-Host "Found $($subscribedSkus.Count) license SKUs" -ForegroundColor Gray
}
catch {
    Write-Host "ERROR: Failed to fetch licenses: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Define the license SKU part names we want to assign
# Based on actual tenant license names for Agent Users
$desiredLicenses = @(
    @{ Name = "Microsoft 365 E5 (no Teams)"; SkuPartNames = @("Microsoft_365_E5_(no_Teams)", "SPE_E5_NOPSTNCONF", "SPE_E5", "ENTERPRISEPREMIUM_NOPSTNCONF", "ENTERPRISEPREMIUM", "SPE_E3", "ENTERPRISEPACK") },
    @{ Name = "Microsoft Teams Enterprise"; SkuPartNames = @("Microsoft_Teams_Enterprise_New", "TEAMS_ENTERPRISE", "TEAMS_EXPLORATORY", "MCOEV", "M365_F1_COMM") },
    @{ Name = "Microsoft Copilot Studio User License"; SkuPartNames = @("VIRTUAL_AGENT_USL", "COPILOT_STUDIO_USER", "Power_Virtual_Agents", "POWER_VIRTUAL_AGENTS_VIRAL", "POWER_VIRTUAL_AGENTS", "PVA") }
)

# Display available licenses
Write-Host ""
Write-Host "Available licenses in your tenant:" -ForegroundColor Cyan
$subscribedSkus | ForEach-Object {
    $available = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
    Write-Host "  • $($_.SkuPartNumber) - Available: $available" -ForegroundColor Gray
}

# Get current user licenses
Write-Host ""
Write-Host "Checking current licenses for Agent User..." -ForegroundColor Yellow
try {
    $user = Get-MgUser -UserId $AgentUserId -Property "assignedLicenses,displayName,userPrincipalName"
    Write-Host "User: $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor Gray
    
    $currentLicenses = $user.AssignedLicenses
    if ($currentLicenses.Count -gt 0) {
        Write-Host "Current licenses:" -ForegroundColor Gray
        foreach ($license in $currentLicenses) {
            $sku = $subscribedSkus | Where-Object { $_.SkuId -eq $license.SkuId }
            Write-Host "  • $($sku.SkuPartNumber)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "No licenses currently assigned." -ForegroundColor Gray
    }
}
catch {
    Write-Host "ERROR: Failed to get user: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Find and assign licenses
Write-Host ""
Write-Host "Assigning licenses..." -ForegroundColor Yellow

$licensesToAssign = @()

foreach ($desiredLicense in $desiredLicenses) {
    $found = $false
    foreach ($skuPartName in $desiredLicense.SkuPartNames) {
        $sku = $subscribedSkus | Where-Object { $_.SkuPartNumber -eq $skuPartName }
        if ($sku) {
            $available = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
            if ($available -gt 0) {
                # Check if already assigned
                $alreadyAssigned = $currentLicenses | Where-Object { $_.SkuId -eq $sku.SkuId }
                if ($alreadyAssigned) {
                    Write-Host "  ✓ $($desiredLicense.Name) ($($sku.SkuPartNumber)) - Already assigned" -ForegroundColor Green
                }
                else {
                    Write-Host "  → $($desiredLicense.Name) ($($sku.SkuPartNumber)) - Will assign" -ForegroundColor Cyan
                    $licensesToAssign += @{ SkuId = $sku.SkuId }
                }
                $found = $true
                break
            }
        }
    }
    if (-not $found) {
        Write-Host "  ⚠ $($desiredLicense.Name) - No available license found" -ForegroundColor Yellow
    }
}

# Assign the licenses
if ($licensesToAssign.Count -gt 0) {
    Write-Host ""
    Write-Host "Applying license assignments..." -ForegroundColor Yellow
    try {
        Set-MgUserLicense -UserId $AgentUserId -AddLicenses $licensesToAssign -RemoveLicenses @()
        Write-Host "Licenses assigned successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to assign licenses: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "You may need to assign licenses manually in the Entra admin center:" -ForegroundColor Yellow
        Write-Host "https://admin.cloud.microsoft/#/users/:/UserDetails/$AgentUserId/LicensesAndApps" -ForegroundColor Cyan
        exit 1
    }
}
else {
    Write-Host ""
    Write-Host "No new licenses to assign." -ForegroundColor Green
}

# Verify final state
Write-Host ""
Write-Host "Verifying license assignment..." -ForegroundColor Yellow
Start-Sleep -Seconds 3
try {
    $user = Get-MgUser -UserId $AgentUserId -Property "assignedLicenses"
    Write-Host "Final assigned licenses:" -ForegroundColor Green
    foreach ($license in $user.AssignedLicenses) {
        $sku = $subscribedSkus | Where-Object { $_.SkuId -eq $license.SkuId }
        Write-Host "  ✓ $($sku.SkuPartNumber)" -ForegroundColor Green
    }
}
catch {
    Write-Host "WARNING: Could not verify licenses: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host "                              LICENSE ASSIGNMENT COMPLETED!                                     " -ForegroundColor Green
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Manual assignment URL (if needed):" -ForegroundColor Gray
Write-Host "https://admin.cloud.microsoft/#/users/:/UserDetails/$AgentUserId/LicensesAndApps" -ForegroundColor Cyan
Write-Host ""
