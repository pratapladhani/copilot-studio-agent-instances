<#
.SYNOPSIS
    Validates all configuration settings for an Agent User setup.

.DESCRIPTION
    This script performs a comprehensive check of all the components required for
    an Agent User to receive messages through Teams and relay them to Copilot Studio.

.PARAMETER ConfigFile
    Path to the a365.config.json file. Defaults to ../a365.config.json

.PARAMETER BlueprintAppId
    The Application (Client) ID of the Agent Blueprint. If not provided, reads from config.

.PARAMETER AgentUserEmail
    The email/UPN of the Agent User. If not provided, reads from config.

.PARAMETER WebAppName
    The name of the Azure Web App hosting the relay. Defaults to "budget-advisor-relay".

.PARAMETER ResourceGroup
    The Azure resource group. Defaults to "rg-agent-bots".

.PARAMETER BotName
    The Azure Bot Service name. Defaults to "budget-advisor-bot".

.EXAMPLE
    .\Test-AgentConfiguration.ps1
    
.EXAMPLE
    .\Test-AgentConfiguration.ps1 -BlueprintAppId "c727c5a9-b404-4861-b10a-9d9bd4c1f3c3" -Verbose
#>

[CmdletBinding()]
param(
    [string]$ConfigFile = "$PSScriptRoot\..\a365.config.json",
    [string]$BlueprintAppId,
    [string]$AgentUserEmail,
    [string]$WebAppName = "budget-advisor-relay",
    [string]$ResourceGroup = "rg-agent-bots",
    [string]$BotName = "budget-advisor-bot"
)

#region Helper Functions
function Write-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Fix = ""
    )
    
    if ($Passed) {
        Write-Host "  [✓] $Name" -ForegroundColor Green
        if ($Details) { Write-Host "      $Details" -ForegroundColor DarkGray }
    }
    else {
        Write-Host "  [✗] $Name" -ForegroundColor Red
        if ($Details) { Write-Host "      $Details" -ForegroundColor Yellow }
        if ($Fix) { Write-Host "      FIX: $Fix" -ForegroundColor Cyan }
    }
    
    return [PSCustomObject]@{
        Name    = $Name
        Passed  = $Passed
        Details = $Details
        Fix     = $Fix
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Test-GraphConnection {
    try {
        $context = Get-MgContext -ErrorAction Stop
        return $null -ne $context
    }
    catch {
        return $false
    }
}
#endregion

#region Main Script
$results = @()
$startTime = Get-Date

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║        AGENT USER CONFIGURATION VALIDATION SCRIPT                 ║" -ForegroundColor Magenta
Write-Host "║        $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                                        ║" -ForegroundColor Magenta
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta

#region Load Configuration
Write-Section "CONFIGURATION LOADING"

# Load config file if exists
$config = $null
if (Test-Path $ConfigFile) {
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    $results += Write-Check -Name "Config file loaded" -Passed $true -Details $ConfigFile
    
    # Extract values from config if not provided as parameters
    if (-not $BlueprintAppId -and $config.agentBlueprintId) {
        $BlueprintAppId = $config.agentBlueprintId
    }
    if (-not $AgentUserEmail -and $config.agentUserPrincipalName) {
        $AgentUserEmail = $config.agentUserPrincipalName
    }
}
else {
    $results += Write-Check -Name "Config file loaded" -Passed $false -Details "File not found: $ConfigFile" -Fix "Create a365.config.json or provide parameters"
}

# Validate required parameters
if (-not $BlueprintAppId) {
    Write-Host "  [!] BlueprintAppId not provided and not found in config" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "  Configuration Values:" -ForegroundColor White
Write-Host "    Blueprint App ID: $BlueprintAppId" -ForegroundColor DarkGray
Write-Host "    Agent User Email: $AgentUserEmail" -ForegroundColor DarkGray
Write-Host "    Web App Name:     $WebAppName" -ForegroundColor DarkGray
Write-Host "    Resource Group:   $ResourceGroup" -ForegroundColor DarkGray
Write-Host "    Bot Name:         $BotName" -ForegroundColor DarkGray
#endregion

#region Prerequisites
Write-Section "PREREQUISITES"

# Check Azure CLI
$azVersion = az version 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
$results += Write-Check -Name "Azure CLI installed" -Passed ($null -ne $azVersion) -Details "Version: $($azVersion.'azure-cli')"

# Check Azure CLI login
$azAccount = az account show 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
$results += Write-Check -Name "Azure CLI logged in" -Passed ($null -ne $azAccount) -Details "Subscription: $($azAccount.name)" -Fix "Run: az login"

# Check Microsoft Graph PowerShell
$mgModule = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication | Select-Object -First 1
$results += Write-Check -Name "Microsoft Graph module installed" -Passed ($null -ne $mgModule) -Details "Version: $($mgModule.Version)" -Fix "Run: Install-Module Microsoft.Graph"

# Check Graph connection
$graphConnected = Test-GraphConnection
$results += Write-Check -Name "Microsoft Graph connected" -Passed $graphConnected -Fix "Run: Connect-MgGraph -Scopes 'Application.Read.All','User.Read.All'"

if (-not $graphConnected) {
    Write-Host ""
    Write-Host "  Connecting to Microsoft Graph..." -ForegroundColor Yellow
    try {
        Connect-MgGraph -Scopes "Application.Read.All", "User.Read.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome
        $graphConnected = Test-GraphConnection
    }
    catch {
        Write-Host "  Failed to connect to Graph: $_" -ForegroundColor Red
    }
}
#endregion

#region Azure Bot Service
Write-Section "AZURE BOT SERVICE"

$bot = az bot show --name $BotName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($bot) {
    $results += Write-Check -Name "Bot exists" -Passed $true -Details "Name: $($bot.name)"
    
    # Check endpoint
    $expectedEndpoint = "https://$WebAppName.azurewebsites.net/api/messages"
    $endpointMatch = $bot.properties.endpoint -eq $expectedEndpoint
    $results += Write-Check -Name "Bot endpoint configured" -Passed $endpointMatch `
        -Details "Current: $($bot.properties.endpoint)" `
        -Fix "az bot update --name $BotName --resource-group $ResourceGroup --endpoint $expectedEndpoint"
    
    # Check MSA App ID matches Blueprint
    $appIdMatch = $bot.properties.msaAppId -eq $BlueprintAppId
    $results += Write-Check -Name "Bot uses Blueprint App ID" -Passed $appIdMatch `
        -Details "Bot App ID: $($bot.properties.msaAppId), Blueprint: $BlueprintAppId"
    
    # Check tenant ID
    $tenantId = $config.tenantId
    $tenantMatch = $bot.properties.msaAppTenantId -eq $tenantId
    $results += Write-Check -Name "Bot tenant configured" -Passed $tenantMatch `
        -Details "Tenant: $($bot.properties.msaAppTenantId)"
    
    # Check channels
    $hasTeams = $bot.properties.configuredChannels -contains "msteams"
    $results += Write-Check -Name "Teams channel enabled" -Passed $hasTeams `
        -Details "Channels: $($bot.properties.configuredChannels -join ', ')" `
        -Fix "Enable Teams channel in Azure Portal"
}
else {
    $results += Write-Check -Name "Bot exists" -Passed $false -Details "Bot not found: $BotName" -Fix "Create Azure Bot Service"
}
#endregion

#region Blueprint Application
Write-Section "AGENT BLUEPRINT (Entra ID Application)"

if ($graphConnected) {
    $blueprint = Get-MgApplication -Filter "appId eq '$BlueprintAppId'" -ErrorAction SilentlyContinue
    
    if ($blueprint) {
        $results += Write-Check -Name "Blueprint application exists" -Passed $true -Details "Display Name: $($blueprint.DisplayName)"
        
        # Check if it's an Agent Identity Blueprint type
        $isAgentBlueprint = $blueprint.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.agentIdentityBlueprint'
        # Note: This check may not work via standard SDK, using Graph API instead
        
        # Check Service Principal
        $blueprintSp = Get-MgServicePrincipal -Filter "appId eq '$BlueprintAppId'" -ErrorAction SilentlyContinue
        $results += Write-Check -Name "Blueprint service principal exists" -Passed ($null -ne $blueprintSp) `
            -Details "Object ID: $($blueprintSp.Id)"
        
        # Check Federated Identity Credentials
        $fics = Invoke-MgGraphRequest -Method GET -Uri "/beta/applications/$($blueprint.Id)/federatedIdentityCredentials" -ErrorAction SilentlyContinue
        $hasFic = $fics.value.Count -gt 0
        $results += Write-Check -Name "Federated Identity Credential configured" -Passed $hasFic `
            -Details "FIC Count: $($fics.value.Count)" `
            -Fix "Run: a365 publish --skip-mos"
        
        if ($hasFic) {
            $fic = $fics.value[0]
            Write-Host "      FIC Name: $($fic.name)" -ForegroundColor DarkGray
            Write-Host "      Issuer: $($fic.issuer)" -ForegroundColor DarkGray
            Write-Host "      Subject: $($fic.subject.Substring(0, [Math]::Min(60, $fic.subject.Length)))..." -ForegroundColor DarkGray
        }
        
        # Check App Role Assignments on Service Principal
        if ($blueprintSp) {
            $roleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $blueprintSp.Id -ErrorAction SilentlyContinue
            $hasRoles = $roleAssignments.Count -gt 0
            $results += Write-Check -Name "App role assignments configured" -Passed $hasRoles `
                -Details "Assignments: $($roleAssignments.Count)"
            
            # Check for specific required role
            $graphSpId = (Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'").Id
            $requiredRoleId = "4aa6e624-eee0-40ab-bdd8-f9639038a614" # AgentIdUser.ReadWrite.IdentityParentedBy
            $hasRequiredRole = $roleAssignments | Where-Object { $_.AppRoleId -eq $requiredRoleId -and $_.ResourceId -eq $graphSpId }
            $results += Write-Check -Name "AgentIdUser.ReadWrite.IdentityParentedBy role assigned" -Passed ($null -ne $hasRequiredRole) `
                -Fix "Run: a365 publish --skip-mos"
        }
        
        # Check Inheritable Permissions
        try {
            $inheritablePerms = Invoke-MgGraphRequest -Method GET -Uri "/beta/applications/microsoft.graph.agentIdentityBlueprint/$($blueprint.Id)/inheritablePermissions" -ErrorAction Stop
            $hasPerms = $inheritablePerms.value.Count -gt 0
            $results += Write-Check -Name "Inheritable permissions configured" -Passed $hasPerms `
                -Details "Permission sets: $($inheritablePerms.value.Count)"
            
            # List configured APIs
            foreach ($perm in $inheritablePerms.value) {
                $apiName = switch ($perm.resourceAppId) {
                    "00000003-0000-0000-c000-000000000000" { "Microsoft Graph" }
                    "8578e004-a5c6-46e7-913e-12f58912df43" { "Power Platform API" }
                    "5a807f24-c9de-44ee-a3a7-329e88a00ffc" { "Messaging Bot API" }
                    default { $perm.resourceAppId }
                }
                Write-Host "        - $apiName" -ForegroundColor DarkGray
            }
        }
        catch {
            $results += Write-Check -Name "Inheritable permissions configured" -Passed $false `
                -Details "Error querying permissions: $_" `
                -Fix "Run: a365 setup permissions"
        }
    }
    else {
        $results += Write-Check -Name "Blueprint application exists" -Passed $false -Details "App ID: $BlueprintAppId" -Fix "Create Blueprint using createAgentBlueprint.ps1"
    }
}
#endregion

#region Agent Identity
Write-Section "AGENT IDENTITY"

if ($graphConnected -and $blueprintSp) {
    # Find Agent Identity by parent
    try {
        $identities = Invoke-MgGraphRequest -Method GET -Uri "/beta/servicePrincipals/Microsoft.Graph.AgentIdentity?`$filter=identityBlueprintId eq '$BlueprintAppId'" -ErrorAction SilentlyContinue
        $agentIdentity = $identities.value | Select-Object -First 1
        
        if ($agentIdentity) {
            $results += Write-Check -Name "Agent Identity exists" -Passed $true `
                -Details "Display Name: $($agentIdentity.displayName), ID: $($agentIdentity.id)"
        }
        else {
            # Try alternate method
            $allIdentities = Invoke-MgGraphRequest -Method GET -Uri "/beta/servicePrincipals?`$filter=servicePrincipalType eq 'ManagedIdentity'" -ErrorAction SilentlyContinue
            $results += Write-Check -Name "Agent Identity exists" -Passed $false `
                -Details "No Agent Identity found for Blueprint" `
                -Fix "Run: createAgenticUser.ps1"
        }
    }
    catch {
        Write-Host "      Note: Could not query Agent Identity directly" -ForegroundColor DarkGray
    }
}
#endregion

#region Agent User
Write-Section "AGENT USER"

if ($graphConnected -and $AgentUserEmail) {
    try {
        $agentUser = Invoke-MgGraphRequest -Method GET -Uri "/beta/users?`$filter=userPrincipalName eq '$AgentUserEmail'" -ErrorAction Stop
        $user = $agentUser.value | Select-Object -First 1
        
        if ($user) {
            $results += Write-Check -Name "Agent User exists" -Passed $true `
                -Details "Display Name: $($user.displayName), ID: $($user.id)"
            
            # Check if it's an agentUser type
            $isAgentUser = $user.'@odata.type' -eq '#microsoft.graph.agentUser'
            $results += Write-Check -Name "User is Agent User type" -Passed $isAgentUser `
                -Details "Type: $($user.'@odata.type')"
            
            # Check account enabled
            $results += Write-Check -Name "Agent User account enabled" -Passed $user.accountEnabled `
                -Fix "Enable the account in Entra ID"
            
            # Check Blueprint linkage
            $linkedToBlueprint = $user.agentIdentityBlueprintId -eq $BlueprintAppId
            $results += Write-Check -Name "Agent User linked to Blueprint" -Passed $linkedToBlueprint `
                -Details "Blueprint ID: $($user.agentIdentityBlueprintId)"
            
            # Check licenses
            $hasLicenses = $user.assignedLicenses.Count -gt 0
            $results += Write-Check -Name "Agent User has licenses" -Passed $hasLicenses `
                -Details "License count: $($user.assignedLicenses.Count)" `
                -Fix "Assign Teams, Exchange, Copilot Studio licenses"
            
            # Check for Teams license specifically
            $userDetails = Invoke-MgGraphRequest -Method GET -Uri "/beta/users/$($user.id)?`$select=assignedPlans" -ErrorAction SilentlyContinue
            $hasTeamsLicense = $userDetails.assignedPlans | Where-Object { $_.service -eq "MicrosoftCommunicationsOnline" -and $_.capabilityStatus -eq "Enabled" }
            $results += Write-Check -Name "Teams license assigned" -Passed ($null -ne $hasTeamsLicense) `
                -Fix "Assign a license that includes Teams"
        }
        else {
            $results += Write-Check -Name "Agent User exists" -Passed $false `
                -Details "User not found: $AgentUserEmail" `
                -Fix "Run: createAgenticUser.ps1"
        }
    }
    catch {
        $results += Write-Check -Name "Agent User exists" -Passed $false -Details "Error: $_"
    }
}
#endregion

#region Web App
Write-Section "AZURE WEB APP"

$webapp = az webapp show --name $WebAppName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($webapp) {
    $results += Write-Check -Name "Web App exists" -Passed $true -Details "URL: https://$($webapp.defaultHostName)"
    
    # Check state
    $isRunning = $webapp.state -eq "Running"
    $results += Write-Check -Name "Web App is running" -Passed $isRunning -Details "State: $($webapp.state)"
    
    # Check App Settings
    $appSettings = az webapp config appsettings list --name $WebAppName --resource-group $ResourceGroup -o json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
    
    $hasAppInsights = $appSettings | Where-Object { $_.name -eq "APPLICATIONINSIGHTS_CONNECTION_STRING" }
    $results += Write-Check -Name "Application Insights configured" -Passed ($null -ne $hasAppInsights) `
        -Fix "Add APPLICATIONINSIGHTS_CONNECTION_STRING app setting"
    
    $hasClientId = $appSettings | Where-Object { $_.name -like "*ClientId*" }
    $results += Write-Check -Name "Client ID configured in app settings" -Passed ($null -ne $hasClientId)
    
    $hasClientSecret = $appSettings | Where-Object { $_.name -like "*ClientSecret*" }
    $results += Write-Check -Name "Client Secret configured in app settings" -Passed ($null -ne $hasClientSecret)
    
    # Check TokenValidation settings (critical for production)
    $tokenValidationEnabled = $appSettings | Where-Object { $_.name -eq "TokenValidation__Enabled" }
    $isTokenValidationEnabled = $tokenValidationEnabled -and $tokenValidationEnabled.value -eq "true"
    $results += Write-Check -Name "TokenValidation enabled (required for production)" -Passed $isTokenValidationEnabled `
        -Details $(if ($tokenValidationEnabled) { "Value: $($tokenValidationEnabled.value)" } else { "Setting not found" }) `
        -Fix "az webapp config appsettings set --name $WebAppName --resource-group $ResourceGroup --settings 'TokenValidation__Enabled=true'"
    
    $tokenValidationAudiences = $appSettings | Where-Object { $_.name -like "TokenValidation__Audiences*" }
    $results += Write-Check -Name "TokenValidation Audiences configured" -Passed ($null -ne $tokenValidationAudiences) `
        -Details $(if ($tokenValidationAudiences) { "Found $($tokenValidationAudiences.Count) audience(s)" } else { "Not configured" }) `
        -Fix "az webapp config appsettings set --name $WebAppName --resource-group $ResourceGroup --settings 'TokenValidation__Audiences__0=<BlueprintAppId>'"
    
    $tokenValidationTenant = $appSettings | Where-Object { $_.name -eq "TokenValidation__TenantId" }
    $results += Write-Check -Name "TokenValidation TenantId configured" -Passed ($null -ne $tokenValidationTenant) `
        -Details $(if ($tokenValidationTenant) { "TenantId: $($tokenValidationTenant.value)" } else { "Not configured" })
    
    # Test endpoint connectivity
    Write-Host ""
    Write-Host "  Testing endpoint connectivity..." -ForegroundColor White
    
    try {
        $response = Invoke-WebRequest -Uri "https://$($webapp.defaultHostName)/" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $results += Write-Check -Name "Web App root endpoint accessible" -Passed ($response.StatusCode -eq 200) `
            -Details "Status: $($response.StatusCode)"
    }
    catch {
        $results += Write-Check -Name "Web App root endpoint accessible" -Passed $false -Details "Error: $_"
    }
    
    try {
        $response = Invoke-WebRequest -Uri "https://$($webapp.defaultHostName)/api/messages" -Method POST -Body "{}" -ContentType "application/json" -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        $results += Write-Check -Name "Messages endpoint responds" -Passed $true -Details "Status: $($response.StatusCode)"
    }
    catch {
        # 400/401/500 are expected for empty/invalid requests - the endpoint exists
        $statusCode = $_.Exception.Response.StatusCode.value__
        $isExpectedError = $statusCode -in @(400, 401, 500)
        $results += Write-Check -Name "Messages endpoint responds" -Passed $isExpectedError `
            -Details "Status: $statusCode (expected for empty request)"
    }
}
else {
    $results += Write-Check -Name "Web App exists" -Passed $false -Details "Not found: $WebAppName" -Fix "Deploy the relay web app"
}
#endregion

#region MOS Titles / Teams App Registration
Write-Section "MOS TITLES / TEAMS APP"

# Note: MOS Titles API requires special authentication, so we just check for the Teams app manifest
$manifestPath = Join-Path $PSScriptRoot "..\AgenticRelay\manifest\manifest.json"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $results += Write-Check -Name "Teams manifest exists" -Passed $true -Details "Version: $($manifest.version)"
    
    $manifestIdMatch = $manifest.id -eq $BlueprintAppId
    $results += Write-Check -Name "Manifest ID matches Blueprint" -Passed $manifestIdMatch `
        -Details "Manifest ID: $($manifest.id)"
    
    # Check agenticUserTemplateManifest
    $templatePath = Join-Path $PSScriptRoot "..\AgenticRelay\manifest\agenticUserTemplateManifest.json"
    if (Test-Path $templatePath) {
        $template = Get-Content $templatePath -Raw | ConvertFrom-Json
        $templateMatch = $template.agentIdentityBlueprintId -eq $BlueprintAppId
        $results += Write-Check -Name "Template Blueprint ID matches" -Passed $templateMatch `
            -Details "Template Blueprint ID: $($template.agentIdentityBlueprintId)"
        
        $hasActivityProtocol = $template.communicationProtocol -eq "activityProtocol"
        $results += Write-Check -Name "Communication protocol is activityProtocol" -Passed $hasActivityProtocol `
            -Details "Protocol: $($template.communicationProtocol)"
    }
}
else {
    $results += Write-Check -Name "Teams manifest exists" -Passed $false -Details "Not found: $manifestPath" -Fix "Run: a365 publish"
}

Write-Host ""
Write-Host "  Note: To verify MOS Titles registration, check Azure Portal > Agent 365 Admin Center" -ForegroundColor DarkGray
Write-Host "  or run: a365 query-entra" -ForegroundColor DarkGray
#endregion

#region Summary
Write-Section "SUMMARY"

$passed = ($results | Where-Object { $_.Passed }).Count
$failed = ($results | Where-Object { -not $_.Passed }).Count
$total = $results.Count

$duration = (Get-Date) - $startTime

Write-Host ""
if ($failed -eq 0) {
    Write-Host "  ✓ ALL CHECKS PASSED ($passed/$total)" -ForegroundColor Green
}
else {
    Write-Host "  RESULTS: $passed passed, $failed failed (out of $total)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Failed checks:" -ForegroundColor Red
    $results | Where-Object { -not $_.Passed } | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor Red
        if ($_.Fix) { Write-Host "      Fix: $($_.Fix)" -ForegroundColor Cyan }
    }
}

Write-Host ""
Write-Host "  Duration: $($duration.TotalSeconds.ToString('F1')) seconds" -ForegroundColor DarkGray
Write-Host ""
#endregion

# Return results for programmatic use
return $results
#endregion
