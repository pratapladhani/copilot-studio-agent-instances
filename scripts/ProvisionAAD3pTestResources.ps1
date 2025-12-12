<#
.SYNOPSIS
    Provisions all the 3P test app auth dependencies for a test tenant.
#>
param(
    [Parameter(Mandatory=$false)]
    [bool] $resetServicePrincipals = $false,
    
    [Parameter(Mandatory=$false)]
    [switch] $SkipSignIn,

    [string] $TenantId = $null
)

$internalApps = @(
    "00000003-0000-0000-c000-000000000000" # Microsoft Graph
)

$tpsTestServerAppId = "6ec511af-06dc-4fe2-b493-63a37bc397b1" # TPS AppServices 3p App (Server)
$tpsTestClientAppId = "caef0b02-8d39-46ab-b28c-f517033d8a21" # TPS AppServices 3p App (Client)

$serverPermissions = @(
    # API permissions (ClientId = TPS AppServices 3p App (Server))
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "00000003-0000-0000-c000-000000000000" # MS Graph
        scope = "SensitiveInfoType.Detect User.Read User.Read.All Files.Read.All InformationProtectionPolicy.Read"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "fb8d773d-7ef8-4ec0-a117-179f88add510" # Enterprise Copilot Platform
        scope = "M365Chat.Read"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "8578e004-a5c6-46e7-913e-12f58912df43" # Power Platform API
        scope = "Connectivity.Connectors.Read Connectivity.Connections.Read PowerVirtualAgents.CopilotAuthorizationChecks"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "e8bdeda8-b4a3-4eed-b307-5e2456238a77" # Office365 Shell SS-Server
        scope = "shellinfo.read"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "0ddb742a-e7dc-4899-a31e-80e797ec7144" # PP API Test
        scope = "Connectivity.Connectors.Read Connectivity.Connections.Read Connectivity.Connections.Write PowerVirtualAgents.CopilotAuthorizationChecks"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "c606301c-f764-4e6b-aa45-7caaaea93c9a" # Office Store
        scope = "UserWxpAddins.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "cc15fd57-2c6c-4117-a88c-83b1d56b4bbe" # Teams
        scope = "apps.read.all Region.ReadWrite user_impersonation"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "a164aee5-7d0a-46bb-9404-37421d58bdf7" # Teams AuthSvc
        scope = "Region.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "5f09333a-842c-47da-a157-57da27fcbca5" # WCSS
        scope = "ShellInfo.Read"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "bb893c22-978d-4cd4-a6f7-bb6cc0d6e6ce" # Bing
        scope = "CopilotEligibility.Read CopilotSettings.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "596c4f3d-a27d-4bcb-a587-3dd6571cc4a9" # BingSearchMSA
        scope = "CopilotEligibility.Read CopilotSettings.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "9ea1ad79-fdb6-4f9a-8bc3-2b70f96e34c7" # Bing Old
        scope = "user.read.all"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "475226c6-020e-4fb2-8a90-7a972cbfc1d4" # PowerApps Service
        scope = "user_impersonation"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "a522f059-bb65-47c0-8934-7db6e5286414" # Power Virtual Agents - Test
        scope = "user_impersonation"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "00000012-0000-0000-c000-000000000000" # Azure Rights Management Services
        scope = "user_impersonation"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "40775b29-2688-46b6-a3b5-b256bd04df9f" # Microsoft Information Protection
        scope = "UnifiedPolicy.User.Read UnifiedPolicy.Tenant.Read"
    }
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "870c4f2e-85b6-4d43-bdda-6ed9a579b725" # Microsoft Information Protection Sync Service
        scope = "UnifiedPolicy.User.Read UnifiedPolicy.Tenant.Read"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "9ec59623-ce40-4dc8-a635-ed0275b5d58a" #purview ecosystem
        scope = "Purview.SensitivityLabels.*,Purview.ProtectionScopes.*"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "ec156f81-f23a-47bd-b16f-9fb2c66420f9" # Exchange
        scope = "Addins.ReadWrite Addins.ReadWrite.All Addins.ReadWrite.Shared MailboxSettings.ReadWrite MailboxSettings.ReadWrite.All MailboxSettings.ReadWrite.Shared"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "9e4a5442-a5c9-4f6f-b03f-5b9fcaaf24b1" # ODC Store User Status
        scope = "DiscoveryConnectedServices.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "66a88757-258c-4c72-893c-3e8bed4d6899" # Substrate Search Service
        scope = "SubstrateSearch-Internal.ReadWrite"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "00000006-0000-0ff1-ce00-000000000000" # Microsoft 365 Admin Center
        scope = "M365AdminPortal.Centro.LicenseRequest"
    },
    @{
        clientId = $tpsTestServerAppId
        consentType = "AllPrincipals"
        resourceId = "322422d3-3e0e-4873-a6c9-d3b4a4c83c0f" # Copilot Tuning Knowledge Serving
        scope = "KnowledgeServing-Internal.ReadWrite"
    }
)

# API permissions (ClientId = TPS AppServices 3p Test (Client))
$clientPermissions = @(
    @{
        clientId = $tpsTestClientAppId
        consentType = "AllPrincipals"
        resourceId = "e8be65d6-d430-4289-a665-51bf2a194bda" # MOS3 1P
        scope = "AuthConfig.Read Title.ReadWrite Title.ReadWrite.All"
    },
    @{
        clientId = $tpsTestClientAppId
        consentType = "AllPrincipals"
        resourceId = $tpsTestServerAppId # TPS AppServices 3p App (Server)
        scope = "AuthConfig.Read Catalog.Read"
    },
    @{
        clientId = $tpsTestClientAppId
        consentType = "AllPrincipals"
        resourceId = "8578e004-a5c6-46e7-913e-12f58912df43" # Power Platform API
        scope = "Connectivity.Connectors.Read Connectivity.Connections.Read"
    },
    @{
        clientId = $tpsTestClientAppId
        consentType = "AllPrincipals"
        resourceId = "0ddb742a-e7dc-4899-a31e-80e797ec7144" # PP API Test
        scope = "Connectivity.Connectors.Read Connectivity.Connections.Read Connectivity.Connections.Write"
    },
    @{
        clientId = $tpsTestClientAppId
        consentType = "AllPrincipals"
        resourceId = "00000003-0000-0000-c000-000000000000" # MS Graph
        scope = "User.Read Files.Read.All InformationProtectionPolicy.Read"
    }
)

$permissions = $clientPermissions + $serverPermissions

$roles = @(
    # API permissions (ClientId = TPS AppServices 3p App (Server))
    @{
        clientId = $tpsTestServerAppId
        resourceId = "00000003-0000-0000-c000-000000000000" # MS Graph
        appRoleIds = @("75359482-378d-4052-8f01-80520e7db3cd", "40dc41bc-0f7e-42ff-89bd-d9516947e474")
    },
    @{
        clientId = $tpsTestServerAppId
        resourceId = "9e4a5442-a5c9-4f6f-b03f-5b9fcaaf24b1" # OfficeServicesManager
        appRoleIds = @("8cba7bad-850f-4d75-904f-8c724092bbc5")
    }
)

function Provision-Application
{
    param([string]$appId)

    Write-Host "Checking if $appId is already provisioned in the tenant"

    # Find if the app is already provisioned.
    $oldServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$appId'" -ErrorAction SilentlyContinue

    # Skip internal apps
    if ($internalApps.Contains($appId))
    {
        Write-Host "Skipping provisioning of internal app $appId"
        return $oldServicePrincipal
    }

    # If the App is already provisioned, remove its service principal.
    if ($null -ne $oldServicePrincipal)
    {
        if (-not $resetServicePrincipals)
        {
            return $oldServicePrincipal
        }
        Write-Host "Removing old provisioning information for $appId from the tenant"
        Remove-MgServicePrincipal -ServicePrincipalId $oldServicePrincipal.id -ErrorAction SilentlyContinue
    }

    Write-Host "Provisioning the App $appId in the tenant"
    $params = @{
        appId = $appId
    }
    
    $newServicePrincipal = New-MgServicePrincipal -BodyParameter $params
    $newServicePrincipal
}

Write-Host "Installing and loading MSGraph modules"
foreach($module in @("Microsoft.Graph.Identity.SignIns", "Microsoft.Graph.Applications", "Microsoft.Graph.Authentication")) {
    try
    {
        Write-Host "Attempting to Load Module '$module'"
        Import-Module -Name $module -ErrorAction Stop
    }
    catch
    {
        Write-Host "Installing MSGraph Module '$module'"
        Install-Module -Name $module -Scope CurrentUser -ErrorAction Stop
        Write-Host "Attempting to Load MSGraph Module '$module'"
        Import-Module -Name $module -ErrorAction Stop
    }
}

# If the user is signed into the wrong tenant, or doesn't have the correct scopes, they need to sign in again even if they passed the skip param
$requiresNewSignIn = $false
if ($SkipSignIn) {
    #Get current graph context and signed -in roles
    $context = Get-MgContext
    $tenantMatches = $context.TenantId -eq $TenantId
    if (-not $tenantMatches -or -not $context.Scopes.Contains("Application.ReadWrite.All")) {
        Write-Host "The current Graph context is associated with the wrong tenant or is not authorized for Application.ReadWrite.All scope. You must sign in again."
        $requiresNewSignIn = $true
    }

    # If the user supplied a tenant ID, and is signed into the right tenant, no need to prompt for consent. If the user did not supply one, ask.
    if (-not $tenantMatches -and -not (Read-Host -Prompt "Tenant $($context.TenantId) is signed in with the correct permissions. Type 'y' to continue consent grant creation in this tenant; type anything else to abort.") -eq 'y') {
        throw
    }
}

if (-not $SkipSignIn -or $requiresNewSignIn) {
    Write-Host "Sign-in using the tenant admin credentials (NOT @microsoft.com) for the tenant you want to provision apps to"
    Start-Sleep -Seconds 1
    # Attempt to force a refresh on log in
    Disconnect-MgGraph
    Connect-MgGraph -Scopes Directory.ReadWrite.All,Application.ReadWrite.All -NoWelcome

    $context = Get-MgContext
    Write-Host "Connected as: $($context.Account) (Tenant: $($context.TenantId))"
    Write-Host "Auth Type: $($context.AuthType)"
}

# HashMap of appId to its service principal object
$appsToProvision = @{}

foreach ($permission in $permissions) 
{
    Write-Host ([environment]::NewLine)

    # Convert AppId to Service Principal Id, as required by Graph API
    $appId = $permission.clientId
    if (-not $appsToProvision.ContainsKey($appId)) 
    {
        $sp = Provision-Application -appId $appId
        $appsToProvision[$appId] = $sp
    }
    $spClientId = $appsToProvision[$appId]

    $appId = $permission.resourceId
    if (-not $appsToProvision.ContainsKey($appId)) 
    {
        $sp = Provision-Application -appId $appId
        $appsToProvision[$appId] = $sp
    }
    $spResourceId = $appsToProvision[$appId]

    Write-Host "Creating permissions grant for client '$($spClientId.displayName)' to call resource '$($spResourceId.displayName)' with scopes '$($permission.scope)'"
    $params = @{
        clientId = $spClientId.id
        consentType = $permission.consentType
        resourceId = $spResourceId.id
        scope = $permission.scope
    }

    # Opportunistically try to create permission grant, and capture both standard and error output
    $output = & New-MgOauth2PermissionGrant -BodyParameter $params -ErrorAction Continue 2>&1
    if ($output -is [System.Management.Automation.ErrorRecord])
    {
        $errorMessage = $output.ErrorDetails.Message

        # Supress errors expected from reruns
        if (-not ($errorMessage.Contains("Permission entry already exists.")))
        {
            Write-Warning "Failed to create permission grant. Error: $errorMessage"
        }
    }
}

foreach ($role in $roles) 
{
    Write-Host ([environment]::NewLine)

    # Convert AppId to Service Principal Id, as required by Graph API
    $appId = $role.clientId
    if (-not $appsToProvision.ContainsKey($appId)) 
    {
        $sp = Provision-Application -appId $appId
        $appsToProvision[$appId] = $sp
    }
    $spClientId = $appsToProvision[$appId]

    $appId = $role.resourceId
    if (-not $appsToProvision.ContainsKey($appId)) 
    {
        $sp = Provision-Application -appId $appId
        $appsToProvision[$appId] = $sp
    }
    $spResourceId = $appsToProvision[$appId]

    foreach($appRoleId in $role.appRoleIds)
    {
        Write-Host "Assigning role to client '$($spClientId.displayName)' for resource '$($spResourceId.displayName)' with role id '$($appRoleId)'"
        $params = @{
            principalId = $spClientId.id
            resourceId = $spResourceId.id
            appRoleId = $appRoleId
        }
    
        # Opportunistically try to create AppRoleAssignedTo, and capture both standard and error output
        $output = & New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $spClientId.id -BodyParameter $params -ErrorAction Continue 2>&1
        if ($output -is [System.Management.Automation.ErrorRecord])
        {
            $errorMessage = $output.ErrorDetails.Message
    
            # Supress errors expected from reruns
            if (-not ($errorMessage.Contains("Permission being assigned already exists")))
            {
                Write-Warning "Failed to create app role assigned to. Error: $errorMessage"
            }
        }
    }
}
