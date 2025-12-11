# Copilot Studio Agent Instances - Project Instructions

## Project Overview

This repository demonstrates how to create and deploy **Agentic Users** (also known as "Digital Workers") in Microsoft 365 that can call **Copilot Studio Agents**. It enables autonomous AI agents to operate within the Microsoft 365 ecosystem.

## Branching Strategy

This project uses a **branch-per-agent** strategy:

- **`master` branch** - Contains the generic framework code, scripts, and documentation. No agent-specific configuration.
- **Agent-specific branches** - Each agent gets its own branch (e.g., `my-admin`, `sales-assistant`, `hr-helper`) containing:
  - Agent-specific config files (e.g., `*-blueprint-config.json`, `*-user-config.json`)
  - Agent-specific `README.md` with use case details, required scopes, and setup instructions
  - Any customizations to the relay service for that agent

### Creating a New Agent Branch

1. Create a new branch from `master`: `git checkout -b <agent-name>`
2. Add config files in `/scripts/` for the blueprint and user
3. Add/update `README.md` with agent-specific details (capabilities, scopes, MCP tools)
4. Update `appsettings.json` with connection details
5. Keep generic framework changes in `master` and merge as needed

## Key Concepts

### Agent Blueprint

- An Entra ID application that serves as a **template** for creating agent identities
- Defines inheritable permissions and scopes that agent instances can use
- Created via `createAgentBlueprint.ps1`
- Must be configured with permissions for:
  - Microsoft Graph (User.ReadBasic.All, Mail.Send, Mail.Read, Chat.Read, Chat.ReadWrite)
  - Power Platform API (CopilotStudio.Copilots.Invoke)
  - Messaging Bot API (all delegated scopes)

### Agent Identity

- A service principal created from the Agent Blueprint
- Represents a specific agent instance
- Created via `createAgenticUser.ps1` using `New-AgentIdentity` function
- Uses the `@odata.type = "Microsoft.Graph.AgentIdentity"` Graph API

### Agent User

- A user principal created from the Agent Identity
- Can operate within Microsoft 365 as a "digital worker"
- Has its own email address, can participate in Teams chats, respond to Word comments
- Uses the `@odata.type = "microsoft.graph.agentUser"` Graph API
- Requires licenses: Teams, Outlook, Microsoft 365, Copilot Studio

## Project Structure

```
/AgenticRelay/           - .NET 9.0 web service (C#)
  AgenticRelay.cs        - Main relay logic for Bot Service ↔ Copilot Studio
  Program.cs             - ASP.NET Core entry point
  AspNetExtensions.cs    - Extension methods for ASP.NET

/scripts/                - PowerShell setup scripts
  DelegatedAgentApplicationCreateConsent.ps1  - Step 1: Grant AgentApplication.Create permission
  createAgentBlueprint.ps1                    - Step 2: Create Agent Blueprint app
  Add-AgentBlueprintPermissions.ps1           - Step 3-5: Configure inheritable permissions
  createAgenticUser.ps1                       - Step 6: Create Agent Identity & Agent User

/appsettings.json        - Configuration for the relay service
```

## Configuration Files

### Blueprint Config (for createAgentBlueprint.ps1)

```json
{
  "TenantId": "<tenant-id>",
  "MsiPrincipalId": "<managed-identity-object-id-optional>",
  "AgentBlueprintDisplayName": "Display Name"
}
```

### Agent User Config (for createAgenticUser.ps1)

```json
{
  "TenantId": "<tenant-id>",
  "AgentBlueprintId": "<blueprint-app-id>",
  "AgentBlueprintClientSecret": "<client-secret>",
  "AgentIdentityDisplayName": "Identity Name",
  "AgentUserDisplayName": "User Display Name",
  "AgentUserPrincipalName": "user@domain.com",
  "UsageLocation": "US"
}
```

### App Settings (for AgenticRelay service)

```json
{
  "ClientId": "<agent-blueprint-app-id>",
  "TenantId": "<tenant-id>",
  "ConnectionUrl": "<copilot-studio-connection-string>",
  "ClientSecret": "<client-secret>"
}
```

## Important App IDs (Well-Known)

| Service                   | App ID                                 |
| ------------------------- | -------------------------------------- |
| Microsoft Graph           | `00000003-0000-0000-c000-000000000000` |
| Power Platform API        | `8578e004-a5c6-46e7-913e-12f58912df43` |
| Messaging Bot API         | `5a807f24-c9de-44ee-a3a7-329e88a00ffc` |
| Microsoft Graph CLI Tools | `14d82eec-204b-4c2f-b7e8-296a70dab67e` |

## Coding Conventions

### PowerShell Scripts

- Use `Invoke-MgGraphRequest` for beta Graph API calls
- Use Microsoft Graph PowerShell SDK cmdlets (e.g., `Get-MgServicePrincipal`, `Update-MgApplication`)
- Support both interactive mode and config file mode via `-ConfigFile` parameter
- Include proper error handling with try/catch blocks
- Use colored output for status messages (Green=success, Yellow=warning, Red=error, Cyan=info)

### C# Code

- Target .NET 9.0
- Use ASP.NET Core minimal APIs pattern
- The AgenticRelay service handles Bot Framework protocol messages

## Common Tasks

### Creating a New Agent

1. Run `DelegatedAgentApplicationCreateConsent.ps1` (one-time, requires Global Admin)
2. Run `createAgentBlueprint.ps1` with config file
3. Run `Add-AgentBlueprintPermissions.ps1` for each resource API
4. Create client secret for the Blueprint
5. Run `createAgenticUser.ps1` with config file
6. Assign licenses to the Agent User in Entra
7. Grant admin consent for required scopes

### Testing the Agent

- Start a chat in Microsoft Teams with the Agent User
- Send an email to the Agent User's email address
- @-mention the agent in a Microsoft Word comment

## Graph API Endpoints Used

- `POST /beta/applications/` - Create Agent Blueprint (with `@odata.type = "Microsoft.Graph.AgentIdentityBlueprint"`)
- `POST /beta/serviceprincipals` - Create Service Principal
- `POST /beta/serviceprincipals/Microsoft.Graph.AgentIdentity` - Create Agent Identity
- `POST /beta/users` - Create Agent User (with `@odata.type = "microsoft.graph.agentUser"`)
- `GET /beta/applications/microsoft.graph.agentIdentityBlueprint/{id}/inheritablePermissions` - Verify permissions
