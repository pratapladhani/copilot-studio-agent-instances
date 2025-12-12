<#
.SYNOPSIS
Grants admin consent for required scopes to an Agent Identity.

.DESCRIPTION
This script opens browser windows to grant admin consent for the delegated scopes 
required by an Agent Identity to operate within Microsoft 365 and call Copilot Studio.

.PARAMETER ConfigFile
Path to a JSON configuration file containing AgentIdentityId and TenantId.

.PARAMETER TenantId
The Tenant ID (required if not using ConfigFile).

.PARAMETER AgentIdentityId
The Agent Identity's Application ID (required if not using ConfigFile).

.PARAMETER OpenInBrowser
If specified, automatically opens the consent URLs in the default browser.

.EXAMPLE
.\Grant-AgentIdentityConsent.ps1 -ConfigFile ".\budget-advisor-user-config.json" -OpenInBrowser

.EXAMPLE
.\Grant-AgentIdentityConsent.ps1 -TenantId "your-tenant-id" -AgentIdentityId "identity-app-id"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$AgentIdentityId,
    
    [Parameter(Mandatory = $false)]
    [switch]$OpenInBrowser
)

# Display script header
Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host "                           Agent Identity Admin Consent Script                                  " -ForegroundColor Cyan
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Reading configuration from file: $ConfigFile" -ForegroundColor Blue
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        $TenantId = $config.TenantId
        $AgentIdentityId = $config.AgentIdentityId
        
        if (-not $AgentIdentityId) {
            Write-Host "ERROR: AgentIdentityId not found in config file. Run createAgenticUser.ps1 first." -ForegroundColor Red
            exit 1
        }
        
        Write-Host "  • Tenant ID: $TenantId" -ForegroundColor Gray
        Write-Host "  • Agent Identity ID: $AgentIdentityId" -ForegroundColor Gray
    }
    catch {
        Write-Host "ERROR: Failed to read configuration file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
elseif (-not $TenantId -or -not $AgentIdentityId) {
    Write-Host "ERROR: Either provide -ConfigFile or both -TenantId and -AgentIdentityId" -ForegroundColor Red
    exit 1
}

# Define the consent URLs
$redirectUri = "https://entra.microsoft.com/TokenAuthorize"
$state = "consent-$(Get-Random)"

# Graph scopes
$graphScopes = "User.ReadBasic.All Mail.Send Mail.Read Chat.Read Chat.ReadWrite"
$graphConsentUrl = "https://login.microsoftonline.com/$TenantId/v2.0/adminconsent?client_id=$AgentIdentityId&scope=$graphScopes&redirect_uri=$redirectUri&state=$state"

# Copilot Studio scope (Power Platform API)
$copilotStudioResourceId = "8578e004-a5c6-46e7-913e-12f58912df43"
$copilotStudioScope = "$copilotStudioResourceId/CopilotStudio.Copilots.Invoke"
$copilotStudioConsentUrl = "https://login.microsoftonline.com/$TenantId/v2.0/adminconsent?client_id=$AgentIdentityId&scope=$copilotStudioScope&redirect_uri=$redirectUri&state=$state"

# MCP Tools scope (Power Platform Connectors)
$mcpResourceId = "0ddb742a-e7dc-4899-a31e-80e797ec7144"
$mcpScope = "$mcpResourceId/Connectivity.Connections.Read"
$mcpConsentUrl = "https://login.microsoftonline.com/$TenantId/v2.0/adminconsent?client_id=$AgentIdentityId&scope=$mcpScope&redirect_uri=$redirectUri&state=$state"

Write-Host ""
Write-Host "The following consent URLs need to be approved by an admin:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. Microsoft Graph Scopes" -ForegroundColor Cyan
Write-Host "   Scopes: $graphScopes" -ForegroundColor Gray
Write-Host "   URL:" -ForegroundColor Gray
Write-Host "   $graphConsentUrl" -ForegroundColor Green
Write-Host ""

Write-Host "2. Copilot Studio (Power Platform API)" -ForegroundColor Cyan
Write-Host "   Scope: CopilotStudio.Copilots.Invoke" -ForegroundColor Gray
Write-Host "   URL:" -ForegroundColor Gray
Write-Host "   $copilotStudioConsentUrl" -ForegroundColor Green
Write-Host ""

Write-Host "3. MCP Tools (Power Platform Connectors) - Optional" -ForegroundColor Cyan
Write-Host "   Scope: Connectivity.Connections.Read" -ForegroundColor Gray
Write-Host "   URL:" -ForegroundColor Gray
Write-Host "   $mcpConsentUrl" -ForegroundColor Green
Write-Host ""

if ($OpenInBrowser) {
    Write-Host "Opening all consent URLs in browser..." -ForegroundColor Yellow
    Write-Host "(Accept each consent dialog, then return here)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "  1. Opening Graph consent page..." -ForegroundColor Cyan
    Start-Process $graphConsentUrl
    Start-Sleep -Seconds 2
    
    Write-Host "  2. Opening Copilot Studio consent page..." -ForegroundColor Cyan
    Start-Process $copilotStudioConsentUrl
    Start-Sleep -Seconds 2
    
    Write-Host "  3. Opening MCP Tools consent page..." -ForegroundColor Cyan
    Start-Process $mcpConsentUrl
    
    Write-Host ""
    Write-Host "All consent pages opened. Press Enter when you've accepted all consents..." -ForegroundColor Yellow
    Read-Host
}
else {
    Write-Host "To open these URLs automatically, run with -OpenInBrowser switch:" -ForegroundColor Gray
    Write-Host "  .\Grant-AgentIdentityConsent.ps1 -ConfigFile `"$ConfigFile`" -OpenInBrowser" -ForegroundColor Cyan
    Write-Host ""
}

# Verify consent was granted
Write-Host ""
Write-Host "Verifying consent grants..." -ForegroundColor Yellow

try {
    Connect-MgGraph -TenantId $TenantId -Scopes "Application.Read.All", "DelegatedPermissionGrant.Read.All" -NoWelcome -ErrorAction Stop
    
    # Get the service principal for the Agent Identity
    $sp = Get-MgServicePrincipal -Filter "appId eq '$AgentIdentityId'" -ErrorAction Stop
    
    if ($sp) {
        Write-Host "Agent Identity Service Principal: $($sp.DisplayName) (ID: $($sp.Id))" -ForegroundColor Gray
        
        # Use a more reliable method to get all grants - query all and filter by clientId
        # Get-MgServicePrincipalOauth2PermissionGrant sometimes misses grants
        $grants = Get-MgOauth2PermissionGrant -All | Where-Object { $_.ClientId -eq $sp.Id }
        
        if ($grants -and $grants.Count -gt 0) {
            Write-Host ""
            Write-Host "Granted permissions:" -ForegroundColor Green
            foreach ($grant in $grants) {
                $resourceSp = Get-MgServicePrincipal -ServicePrincipalId $grant.ResourceId -ErrorAction SilentlyContinue
                $resourceName = if ($resourceSp) { $resourceSp.DisplayName } else { $grant.ResourceId }
                Write-Host "  ✓ $resourceName" -ForegroundColor Green
                Write-Host "    Scopes: $($grant.Scope)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host ""
            Write-Host "⚠ No permission grants found yet." -ForegroundColor Yellow
            Write-Host "  Please open the consent URLs above and accept the permissions." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "Could not verify grants (this is normal if running without Graph connection): $($_.Exception.Message)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host "                                    CONSENT SCRIPT COMPLETED                                    " -ForegroundColor Green
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "After accepting all consent prompts, you should see 'admin_consent=True' in the redirect URL." -ForegroundColor Gray
Write-Host ""
