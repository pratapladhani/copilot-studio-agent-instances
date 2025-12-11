# Kairo Setup Scripts

This directory contains scripts to help you set up Agent Blueprint, Agent Identities, and Agent Users for the Kairo platform.

## Scripts Overview

| Script | Purpose | Run Once/Per Agent |
|--------|---------|-------------------|
| `DelegatedAgentApplicationCreateConsent.ps1` | Grant permissions to create Agent Applications | Once |
| `createAgentBlueprint.ps1` | Create the Agent Blueprint | Once |
| `Add-AgentBlueprintPermissions.ps1` | Configure inheritable permissions | Once |
| `createAzureBotService.ps1` | Create Azure Bot Service and Teams channel | Once |
| `createAgenticUser.ps1` | Create Agent Identity and Agent User | Per Agent |
| `Configure-CopilotStudioAgent.ps1` | Connect AgenticRelay to a Copilot Studio Agent | Once |
| `Verify-AgentSetup.ps1` | Verify all setup steps are complete | As needed |

## Quick Start

```powershell
# Step 1: Grant permissions (requires Global Admin)
.\DelegatedAgentApplicationCreateConsent.ps1 -TenantId "<tenant-id>" -CallingAppId "14d82eec-204b-4c2f-b7e8-296a70dab67e"

# Step 2: Create Agent Blueprint
.\createAgentBlueprint.ps1 -ConfigFile ".\config.json"

# Step 3: Add Power Platform API permissions
.\Add-AgentBlueprintPermissions.ps1 -TenantId "<tenant-id>" -AgentBlueprintAppId "<app-id>" -ResourceAppId "8578e004-a5c6-46e7-913e-12f58912df43" -Scopes "CopilotStudio.Copilots.Invoke"

# Step 4: Add Messaging Bot API permissions
.\Add-AgentBlueprintPermissions.ps1 -TenantId "<tenant-id>" -AgentBlueprintAppId "<app-id>" -ResourceAppId "5a807f24-c9de-44ee-a3a7-329e88a00ffc" -AllAllowed

# Step 5: Create Agent Blueprint Client Secret (needed for Step 8)
az ad app credential reset --id "<agent-blueprint-app-id>" --display-name "AgentBlueprintSecret" --years 1
# ⚠️ Save the password from the output!

# Step 6: Create Azure Bot Service (one-time setup)
.\createAzureBotService.ps1 -TenantId "<tenant-id>" -AgentBlueprintAppId "<app-id>" -ResourceGroup "<rg-name>" -BotName "<bot-name>" -MessagingEndpoint "https://<your-app>.azurewebsites.net/api/messages" -EnableTeamsChannel

# Step 7: Verify setup
.\Verify-AgentSetup.ps1

# Step 8: Create Agent Identity and Agent User (per agent)
.\createAgenticUser.ps1 -ConfigFile "agentuser-config.json"
# You'll be prompted for the secret from Step 5

# Step 9: Configure Copilot Studio Agent connection
.\Configure-CopilotStudioAgent.ps1
```

---

## Creating the Agent Blueprint

### Prerequisite – Script #1

Callers of this script (users in your tenant) are required to be **Global Admins** to create Agent Applications.

Also, for you to be able to create the Agent Blueprint, you need to grant the `AgentApplication.Create` permission to the Microsoft Graph Command Line Tools application. For that, you can execute this script in PowerShell. Copied from [here](https://learn.microsoft.com/en-us/graph/permissions-reference#agentapplication-permissions):

- `DelegatedAgentApplicationCreateConsent.ps1`

You will need to provide:
- **Tenant ID** – navigate to "Tenant properties" for this information
- **Calling App ID** – use `14d82eec-204b-4c2f-b7e8-296a70dab67e` for Microsoft Graph Command Line Tools

### Creating the Agent Blueprint – Script #2

To create the Agent Blueprint and link it to your App Service, run this script in PowerShell:

- `createAgentBlueprint.ps1` (interactive mode)
- `createAgentBlueprint.ps1 -ConfigFile "config.json"` (config mode)

You will need to provide:
- **Tenant ID**
- **MSI Principal ID** – this is your Object (principal) ID of the managed identity for the App Service that you created

Sample `config.json`, replace with appropriate values:
```json
{
    "TenantId": "",
    "MsiPrincipalId": ""
}
```

## Granting Consent for the Agent Blueprint and Enabling Inheritance

We can grant consent at Agent Blueprint level and choose which of these permissions should be passed down to the agent identities being created from this blueprint.

### Assign Necessary Permissions to Agent Blueprint

Navigate to this URL to automatically give permissions to your Agent Blueprint to necessary scopes needed by your agent and for token authorization:

```
https://login.microsoftonline.com/{TenantId}/v2.0/adminconsent?client_id={AgentApplicationIdentity}&scope={Scopes}&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123
```

**Example for Graph scopes:**
```
https://login.microsoftonline.com/5369a35c-46a5-4677-8ff9-2e65587654e7/v2.0/adminconsent?client_id=a9c3e0c7-b2ce-46db-adf7-d60120faa0cd&scope=Mail.ReadWrite Mail.Send Chat.ReadWrite&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123
```

**Example for non-Graph scopes** (Connectivity.Connections.Read needed for MCP Tools):
```
https://login.microsoftonline.com/5369a35c-46a5-4677-8ff9-2e65587654e7/v2.0/adminconsent?client_id=416fa9f7-e69d-4e7b-8c8f-7b116634d34e&scope=0ddb742a-e7dc-4899-a31e-80e797ec7144/Connectivity.Connections.Read&redirect_uri=https://entra.microsoft.com/TokenAuthorize&state=xyz123
```

For non-Graph scopes note that you need to add the resourceId to the scope: `0ddb742a-e7dc-4899-a31e-80e797ec7144/Connectivity.Connections.Read` in the example above.

Once this is done, you should be able to see the permissions granted in the Azure portal for your agent blueprint.

### Enable Consent Permission Inheritance for the Agent Blueprint

Once the inheritance is set, all Agent Identities that are created get the same consents defined in the inheritance allowed list no matter when the AAI created (i.e., before or after the inheritance call is done).

```http
POST https://graph.microsoft.com/beta/applications/microsoft.graph.agentIdentityBlueprint/{ObjectId of AA}/inheritablePermissions

Content-Type: application/json
{
  "resourceAppId": "ResourceId of the app that we are giving the consent. e.g, Graph Resource ID"
  "inheritableScopes": {
    "@odata.type": "microsoft.graph.enumeratedScopes",
    "scopes": [
          // ... list of scope .. //
    ]
  }
}
```

**Example:**
```http
POST https://graph.microsoft.com/beta/applications/microsoft.graph.agentIdentityBlueprint/45f01fc6-c60e-4458-ac36-731d2ddb090f/inheritablePermissions

Content-Type: application/json
{
  "resourceAppId": "00000003-0000-0000-c000-000000000000",
  "inheritableScopes": {
    "@odata.type": "microsoft.graph.enumeratedScopes",
    "scopes": [
      "Mail.Read",
      "Mail.Send", 
      "Mail.ReadWrite",
      "Chat.ReadWrite",
      "User.ReadBasic.All"
    ]
  }
}
```

Refer to [Agent User README](README_AgentUserCreation.md) for next steps on creation agent identity, user and granting permissions at identity level.

---

## Creating Agent Blueprint Client Secret

Before creating Agent Identities, you need a client secret for the Agent Blueprint. This is used to authenticate when creating Agent Identities.

**Create the secret:**
```powershell
az ad app credential reset --id "<agent-blueprint-app-id>" --display-name "AgentBlueprintSecret" --years 1
```

**⚠️ Important:** Save the `password` from the output! You'll need it when running `createAgenticUser.ps1`.

The secret is only displayed once. If you lose it, you'll need to create a new one.

---

## Creating Azure Bot Service

The Azure Bot Service acts as the routing layer between Microsoft 365 channels (Teams, Outlook) and your AgenticRelay backend. **This only needs to be done once per Agent Blueprint.**

### createAzureBotService.ps1

**Prerequisites:**
- Azure CLI (`az`) - Must be logged in
- An Agent Blueprint already created
- AgenticRelay App Service already deployed

**Interactive mode:**
```powershell
.\createAzureBotService.ps1 -EnableTeamsChannel
```

**With parameters:**
```powershell
.\createAzureBotService.ps1 `
  -TenantId "<tenant-id>" `
  -AgentBlueprintAppId "<agent-blueprint-app-id>" `
  -ResourceGroup "rg-agent365" `
  -BotName "bot-agent365" `
  -BotDisplayName "Agent 365 Bot" `
  -MessagingEndpoint "https://app-agenticrelay-365.azurewebsites.net/api/messages" `
  -EnableTeamsChannel
```

**With config file:**

Sample `bot-config.json`:
```json
{
    "TenantId": "",
    "AgentBlueprintAppId": "",
    "ResourceGroup": "rg-agent365",
    "BotName": "bot-agent365",
    "BotDisplayName": "Agent 365 Bot",
    "MessagingEndpoint": "https://app-agenticrelay-365.azurewebsites.net/api/messages",
    "EnableTeamsChannel": true
}
```

```powershell
.\createAzureBotService.ps1 -ConfigFile "bot-config.json"
```

### After Running the Script

Navigate to the Teams Developer Portal to connect notifications:
1. Go to: https://dev.teams.microsoft.com/tools/agent-blueprint
2. Select your Agent Blueprint
3. Go to **Configuration**
4. Set **Agent type** = **Bot based**
5. Paste the Bot App ID (same as Agent Blueprint App ID)
6. Save

---

## Configuring Copilot Studio Agent Connection

### Configure-CopilotStudioAgent.ps1

This script connects your deployed AgenticRelay App Service to a specific Copilot Studio Agent.

**Prerequisites:**
- Power Platform CLI (`pac`) - Install with: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`
- Azure CLI (`az`) - Must be logged in
- A deployed App Service running AgenticRelay
- A Copilot Studio Agent to connect to

**Interactive mode (recommended):**
```powershell
.\Configure-CopilotStudioAgent.ps1
```

The script will:
1. Authenticate to Power Platform
2. List your environments and let you select one
3. List Copilot Studio agents in that environment
4. Get the Direct Connect URL for the selected agent
5. Prompt for Agent Identity credentials
6. Update the App Service configuration
7. Optionally restart the App Service

**With parameters:**
```powershell
.\Configure-CopilotStudioAgent.ps1 `
  -ResourceGroup "rg-agent365" `
  -AppServiceName "app-agenticrelay-365" `
  -AgentIdentityAppId "<agent-identity-app-id>" `
  -AgentIdentitySecret "<secret>" `
  -EnvironmentId "<power-platform-env-id>" `
  -AgentSchemaName "<agent-schema-name>"
```

**Skip Agent Identity (if already configured):**
```powershell
.\Configure-CopilotStudioAgent.ps1 -SkipAgentIdentity
```

---

## Verifying Setup

### Verify-AgentSetup.ps1

This script verifies that all setup steps have been completed correctly.

**Usage:**
```powershell
.\Verify-AgentSetup.ps1
```

**What it checks:**
1. Agent Blueprint Application exists
2. Service Principal exists
3. Federated Identity Credential (MSI link)
4. OAuth2 Scopes (access_agent)
5. Inheritable Permissions
6. Admin Consent Grants (Microsoft Graph)
7. App Service is running
8. Power Platform API permissions
9. Messaging Bot API permissions

**With custom parameters:**
```powershell
.\Verify-AgentSetup.ps1 `
  -TenantId "<tenant-id>" `
  -AgentBlueprintAppId "<app-id>" `
  -ServicePrincipalId "<sp-id>" `
  -MsiPrincipalId "<msi-id>" `
  -AppServiceUrl "https://your-app.azurewebsites.net"
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Agent Blueprint                                  │
│                    (Permission template)                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          Agent Identity                                  │
│                    (App registration per agent)                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                            Agent User                                    │
│                    (User identity for the agent)                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     AgenticRelay (App Service)                           │
│              Connects Agent User to Copilot Studio Agent                │
│                                                                          │
│  appsettings.json / App Settings:                                       │
│    - CopilotStudioAgent__DirectConnectUrl                               │
│    - Connections__ServiceConnection__Settings__ClientId                  │
│    - Connections__ServiceConnection__Settings__ClientSecret             │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       Copilot Studio Agent                               │
│                    (Your AI agent logic)                                │
└─────────────────────────────────────────────────────────────────────────┘
```

