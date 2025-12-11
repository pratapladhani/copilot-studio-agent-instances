<#
.SYNOPSIS
Verifies the Agent 365 Blueprint setup is complete and correct.

.DESCRIPTION
This script checks all components of the Agent Blueprint setup:
- Agent Blueprint Application
- Service Principal
- Federated Identity Credential (MSI link)
- OAuth2 Scopes
- Inheritable Permissions
- Admin Consent Grants
- App Service deployment

.PARAMETER TenantId
The Azure AD Tenant ID.

.PARAMETER AgentBlueprintAppId
The Application (client) ID of the Agent Blueprint.

.PARAMETER AgentBlueprintObjectId
The Object ID of the Agent Blueprint application.

.PARAMETER ServicePrincipalId
The Object ID of the Agent Blueprint's Service Principal.

.PARAMETER MsiPrincipalId
The Object (principal) ID of the App Service's managed identity.

.PARAMETER AppServiceUrl
The URL of the deployed App Service.

.EXAMPLE
.\Verify-AgentSetup.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId = "b4d63962-b17c-4e17-b121-b6d6e227ba06",
    
    [Parameter(Mandatory = $false)]
    [string]$AgentBlueprintAppId = "6ca4a30f-7bc3-4198-a30a-a3a7c8be9326",
    
    [Parameter(Mandatory = $false)]
    [string]$AgentBlueprintObjectId = "6ca4a30f-7bc3-4198-a30a-a3a7c8be9326",
    
    [Parameter(Mandatory = $false)]
    [string]$ServicePrincipalId = "a29638ba-fa8d-4397-a4ec-5a9570277324",
    
    [Parameter(Mandatory = $false)]
    [string]$MsiPrincipalId = "3990b8e7-9665-44eb-9cd8-50014430633d",
    
    [Parameter(Mandatory = $false)]
    [string]$AppServiceUrl = "https://app-agenticrelay-365.azurewebsites.net"
)

# Colors for output
$SuccessColor = "Green"
$FailColor = "Red"
$WarnColor = "Yellow"
$InfoColor = "Cyan"

function Write-StepHeader {
    param([string]$StepNumber, [string]$Title)
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor $InfoColor
    Write-Host "Step $StepNumber : $Title" -ForegroundColor $InfoColor
    Write-Host "=" * 80 -ForegroundColor $InfoColor
}

function Write-CheckResult {
    param([string]$Check, [bool]$Success, [string]$Details = "")
    if ($Success) {
        Write-Host "  [✓] $Check" -ForegroundColor $SuccessColor
    }
    else {
        Write-Host "  [✗] $Check" -ForegroundColor $FailColor
    }
    if ($Details) {
        Write-Host "      $Details" -ForegroundColor Gray
    }
}

$totalChecks = 0
$passedChecks = 0

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $InfoColor
Write-Host "║              AGENT 365 BLUEPRINT - SETUP VERIFICATION                        ║" -ForegroundColor $InfoColor
Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $InfoColor
Write-Host ""
Write-Host "Configuration:" -ForegroundColor $InfoColor
Write-Host "  Tenant ID:              $TenantId"
Write-Host "  Blueprint App ID:       $AgentBlueprintAppId"
Write-Host "  Blueprint Object ID:    $AgentBlueprintObjectId"
Write-Host "  Service Principal ID:   $ServicePrincipalId"
Write-Host "  MSI Principal ID:       $MsiPrincipalId"
Write-Host "  App Service URL:        $AppServiceUrl"

# ============================================================================
# Step 1: Verify Agent Blueprint Application
# ============================================================================
Write-StepHeader "1" "Agent Blueprint Application"

try {
    $blueprint = Get-MgApplication -Filter "appId eq '$AgentBlueprintAppId'" -ErrorAction Stop
    $totalChecks++
    if ($blueprint) {
        $passedChecks++
        Write-CheckResult "Agent Blueprint exists" $true "DisplayName: $($blueprint.DisplayName)"
        
        # Check if it's the correct type
        $totalChecks++
        if ($blueprint.DisplayName -eq "Agent 365 Blueprint") {
            $passedChecks++
            Write-CheckResult "Display name is correct" $true
        }
        else {
            Write-CheckResult "Display name is correct" $false "Expected 'Agent 365 Blueprint', got '$($blueprint.DisplayName)'"
        }
    }
    else {
        Write-CheckResult "Agent Blueprint exists" $false "Application not found"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Agent Blueprint exists" $false $_.Exception.Message
}

# ============================================================================
# Step 2: Verify Service Principal
# ============================================================================
Write-StepHeader "2" "Service Principal"

try {
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AgentBlueprintAppId'" -ErrorAction Stop
    $totalChecks++
    if ($sp) {
        $passedChecks++
        Write-CheckResult "Service Principal exists" $true "Object ID: $($sp.Id)"
        
        $totalChecks++
        if ($sp.Id -eq $ServicePrincipalId) {
            $passedChecks++
            Write-CheckResult "Service Principal ID matches" $true
        }
        else {
            Write-CheckResult "Service Principal ID matches" $false "Expected '$ServicePrincipalId', got '$($sp.Id)'"
        }
    }
    else {
        Write-CheckResult "Service Principal exists" $false "Service Principal not found"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Service Principal exists" $false $_.Exception.Message
}

# ============================================================================
# Step 3: Verify Federated Identity Credential
# ============================================================================
Write-StepHeader "3" "Federated Identity Credential (MSI Link)"

try {
    $fedCreds = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/applications/$AgentBlueprintObjectId/federatedIdentityCredentials" `
        -ErrorAction Stop
    
    $totalChecks++
    if ($fedCreds.value -and $fedCreds.value.Count -gt 0) {
        $passedChecks++
        Write-CheckResult "Federated credentials exist" $true "Count: $($fedCreds.value.Count)"
        
        # Check for MSI credential
        $msiCred = $fedCreds.value | Where-Object { $_.subject -eq $MsiPrincipalId }
        $totalChecks++
        if ($msiCred) {
            $passedChecks++
            Write-CheckResult "MSI credential linked" $true "Name: $($msiCred.name)"
        }
        else {
            Write-CheckResult "MSI credential linked" $false "No credential found with subject '$MsiPrincipalId'"
        }
    }
    else {
        Write-CheckResult "Federated credentials exist" $false "No credentials found"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Federated credentials exist" $false $_.Exception.Message
}

# ============================================================================
# Step 4: Verify OAuth2 Scopes
# ============================================================================
Write-StepHeader "4" "OAuth2 Permission Scopes"

try {
    $app = Get-MgApplication -Filter "appId eq '$AgentBlueprintAppId'" -ErrorAction Stop
    $scopes = $app.Api.Oauth2PermissionScopes
    
    $totalChecks++
    if ($scopes -and $scopes.Count -gt 0) {
        $passedChecks++
        Write-CheckResult "OAuth2 scopes configured" $true "Count: $($scopes.Count)"
        
        # Check for access_agent scope
        $accessAgentScope = $scopes | Where-Object { $_.Value -eq "access_agent" }
        $totalChecks++
        if ($accessAgentScope) {
            $passedChecks++
            Write-CheckResult "access_agent scope exists" $true "Enabled: $($accessAgentScope.IsEnabled)"
        }
        else {
            Write-CheckResult "access_agent scope exists" $false
        }
        
        # List all scopes
        foreach ($scope in $scopes) {
            Write-Host "      - $($scope.Value) (Enabled: $($scope.IsEnabled))" -ForegroundColor Gray
        }
    }
    else {
        Write-CheckResult "OAuth2 scopes configured" $false "No scopes found"
    }
    
    # Check Identifier URI
    $totalChecks++
    $expectedUri = "api://$AgentBlueprintAppId"
    if ($app.IdentifierUris -contains $expectedUri) {
        $passedChecks++
        Write-CheckResult "Identifier URI configured" $true $expectedUri
    }
    else {
        Write-CheckResult "Identifier URI configured" $false "Expected '$expectedUri'"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "OAuth2 scopes configured" $false $_.Exception.Message
}

# ============================================================================
# Step 5: Verify Inheritable Permissions
# ============================================================================
Write-StepHeader "5" "Inheritable Permissions"

try {
    $inheritablePerms = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/applications/microsoft.graph.agentIdentityBlueprint/$AgentBlueprintObjectId/inheritablePermissions" `
        -Headers @{ "OData-Version" = "4.0" } `
        -ErrorAction Stop
    
    $totalChecks++
    if ($inheritablePerms.value -and $inheritablePerms.value.Count -gt 0) {
        $passedChecks++
        Write-CheckResult "Inheritable permissions configured" $true "Count: $($inheritablePerms.value.Count)"
        
        foreach ($perm in $inheritablePerms.value) {
            $resourceName = switch ($perm.resourceAppId) {
                "00000003-0000-0000-c000-000000000000" { "Microsoft Graph" }
                "8578e004-a5c6-46e7-913e-12f58912df43" { "Power Platform API" }
                "5a807f24-c9de-44ee-a3a7-329e88a00ffc" { "Messaging Bot API" }
                default { $perm.resourceAppId }
            }
            Write-Host "      - $resourceName" -ForegroundColor Gray
            if ($perm.inheritableScopes.scopes) {
                Write-Host "        Scopes: $($perm.inheritableScopes.scopes -join ', ')" -ForegroundColor Gray
            }
            elseif ($perm.inheritableScopes.kind -eq "allAllowed") {
                Write-Host "        Scopes: All Allowed" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-CheckResult "Inheritable permissions configured" $false "No inheritable permissions found"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Inheritable permissions configured" $false $_.Exception.Message
}

# ============================================================================
# Step 6: Verify Admin Consent Grant (Microsoft Graph)
# ============================================================================
Write-StepHeader "6" "Admin Consent Grants"

try {
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction Stop
    $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$ServicePrincipalId' and resourceId eq '$($graphSp.Id)'" -ErrorAction Stop
    
    $totalChecks++
    if ($grants) {
        $passedChecks++
        Write-CheckResult "Microsoft Graph consent granted" $true
        foreach ($grant in $grants) {
            Write-Host "      ConsentType: $($grant.ConsentType)" -ForegroundColor Gray
            Write-Host "      Scopes: $($grant.Scope)" -ForegroundColor Gray
        }
    }
    else {
        Write-CheckResult "Microsoft Graph consent granted" $false "No grants found"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Microsoft Graph consent granted" $false $_.Exception.Message
}

# ============================================================================
# Step 7: Verify App Service
# ============================================================================
Write-StepHeader "7" "App Service Deployment"

try {
    $response = Invoke-WebRequest -Uri $AppServiceUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    
    $totalChecks++
    if ($response.StatusCode -eq 200) {
        $passedChecks++
        Write-CheckResult "App Service is reachable" $true "Status: $($response.StatusCode)"
        
        $totalChecks++
        if ($response.Content -like "*Microsoft Agents SDK*") {
            $passedChecks++
            Write-CheckResult "App Service returns expected content" $true
        }
        else {
            Write-CheckResult "App Service returns expected content" $false "Unexpected response content"
        }
    }
    else {
        Write-CheckResult "App Service is reachable" $false "Status: $($response.StatusCode)"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "App Service is reachable" $false $_.Exception.Message
}

# ============================================================================
# Step 8: Verify Power Platform API Permissions (if configured)
# ============================================================================
Write-StepHeader "8" "Power Platform API Permissions (CopilotStudio.Copilots.Invoke)"

try {
    $ppSp = Get-MgServicePrincipal -Filter "appId eq '8578e004-a5c6-46e7-913e-12f58912df43'" -ErrorAction SilentlyContinue
    
    if ($ppSp) {
        $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$ServicePrincipalId' and resourceId eq '$($ppSp.Id)'" -ErrorAction SilentlyContinue
        
        $totalChecks++
        if ($grants -and $grants.Scope -like "*CopilotStudio.Copilots.Invoke*") {
            $passedChecks++
            Write-CheckResult "CopilotStudio.Copilots.Invoke granted" $true
            Write-Host "      Scopes: $($grants.Scope)" -ForegroundColor Gray
        }
        else {
            Write-CheckResult "CopilotStudio.Copilots.Invoke granted" $false "Run Add-AgentBlueprintPermissions.ps1 for Power Platform API"
        }
    }
    else {
        $totalChecks++
        Write-CheckResult "Power Platform API Service Principal" $false "Not found in tenant - may need to be provisioned"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Power Platform API permissions" $false $_.Exception.Message
}

# ============================================================================
# Step 9: Verify Messaging Bot API Permissions (if configured)
# ============================================================================
Write-StepHeader "9" "Messaging Bot API Permissions"

try {
    $botSp = Get-MgServicePrincipal -Filter "appId eq '5a807f24-c9de-44ee-a3a7-329e88a00ffc'" -ErrorAction SilentlyContinue
    
    if ($botSp) {
        $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$ServicePrincipalId' and resourceId eq '$($botSp.Id)'" -ErrorAction SilentlyContinue
        
        $totalChecks++
        if ($grants) {
            $passedChecks++
            Write-CheckResult "Messaging Bot API consent granted" $true
            Write-Host "      Scopes: $($grants.Scope)" -ForegroundColor Gray
        }
        else {
            Write-CheckResult "Messaging Bot API consent granted" $false "Run Add-AgentBlueprintPermissions.ps1 with -AllAllowed"
        }
    }
    else {
        $totalChecks++
        Write-CheckResult "Messaging Bot API Service Principal" $false "Not found in tenant - may need to be provisioned"
    }
}
catch {
    $totalChecks++
    Write-CheckResult "Messaging Bot API permissions" $false $_.Exception.Message
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $InfoColor
Write-Host "║                              VERIFICATION SUMMARY                            ║" -ForegroundColor $InfoColor
Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $InfoColor
Write-Host ""

$percentage = if ($totalChecks -gt 0) { [math]::Round(($passedChecks / $totalChecks) * 100, 1) } else { 0 }

if ($passedChecks -eq $totalChecks) {
    Write-Host "  Result: ALL CHECKS PASSED ($passedChecks/$totalChecks)" -ForegroundColor $SuccessColor
}
elseif ($percentage -ge 70) {
    Write-Host "  Result: MOSTLY PASSED ($passedChecks/$totalChecks - $percentage%)" -ForegroundColor $WarnColor
}
else {
    Write-Host "  Result: NEEDS ATTENTION ($passedChecks/$totalChecks - $percentage%)" -ForegroundColor $FailColor
}

Write-Host ""
Write-Host "  Checks Passed: $passedChecks" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { $SuccessColor } else { $WarnColor })
Write-Host "  Checks Failed: $($totalChecks - $passedChecks)" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { $SuccessColor } else { $FailColor })
Write-Host "  Total Checks:  $totalChecks" -ForegroundColor $InfoColor
Write-Host ""
