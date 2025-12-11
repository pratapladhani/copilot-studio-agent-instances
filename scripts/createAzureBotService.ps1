<#
.SYNOPSIS
    Creates an Azure Bot Service resource using the Agent Blueprint App ID.

.DESCRIPTION
    This script creates an Azure Bot Service that uses the same App ID as your Agent Blueprint.
    The Bot Service acts as a routing layer that connects Microsoft 365 channels (Teams, Outlook)
    to your AgenticRelay backend.

    This only needs to be run ONCE per Agent Blueprint.

.PARAMETER TenantId
    The Azure AD Tenant ID.

.PARAMETER AgentBlueprintAppId
    The Application (client) ID of the Agent Blueprint.

.PARAMETER ResourceGroup
    The Azure resource group name where the bot will be created.

.PARAMETER BotName
    The name of the Azure Bot Service resource.

.PARAMETER BotDisplayName
    The display name for the bot.

.PARAMETER MessagingEndpoint
    The messaging endpoint URL (your AgenticRelay app's /api/messages endpoint).

.PARAMETER Sku
    The pricing tier for the bot. Default is S1.

.PARAMETER EnableTeamsChannel
    If specified, enables the Microsoft Teams channel for the bot.

.PARAMETER ConfigFile
    Path to a JSON configuration file containing the above parameters.

.EXAMPLE
    .\createAzureBotService.ps1 -TenantId "your-tenant-id" -AgentBlueprintAppId "your-app-id" -ResourceGroup "rg-agent365" -BotName "bot-agent365" -MessagingEndpoint "https://your-app.azurewebsites.net/api/messages" -EnableTeamsChannel

.EXAMPLE
    .\createAzureBotService.ps1 -ConfigFile "bot-config.json"
#>

param(
    [string]$TenantId,
    [string]$AgentBlueprintAppId,
    [string]$ResourceGroup,
    [string]$BotName,
    [string]$BotDisplayName,
    [string]$MessagingEndpoint,
    [string]$Sku = "S1",
    [switch]$EnableTeamsChannel,
    [string]$ConfigFile
)

# Load from config file if provided
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Loading configuration from $ConfigFile..." -ForegroundColor Cyan
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    
    if (-not $TenantId -and $config.TenantId) { $TenantId = $config.TenantId }
    if (-not $AgentBlueprintAppId -and $config.AgentBlueprintAppId) { $AgentBlueprintAppId = $config.AgentBlueprintAppId }
    if (-not $ResourceGroup -and $config.ResourceGroup) { $ResourceGroup = $config.ResourceGroup }
    if (-not $BotName -and $config.BotName) { $BotName = $config.BotName }
    if (-not $BotDisplayName -and $config.BotDisplayName) { $BotDisplayName = $config.BotDisplayName }
    if (-not $MessagingEndpoint -and $config.MessagingEndpoint) { $MessagingEndpoint = $config.MessagingEndpoint }
    if ($config.Sku) { $Sku = $config.Sku }
    if ($config.EnableTeamsChannel) { $EnableTeamsChannel = $true }
}

# Interactive prompts for missing required values
if (-not $TenantId) {
    $TenantId = Read-Host "Enter your Tenant ID"
}

if (-not $AgentBlueprintAppId) {
    $AgentBlueprintAppId = Read-Host "Enter your Agent Blueprint App ID"
}

if (-not $ResourceGroup) {
    $ResourceGroup = Read-Host "Enter the Azure Resource Group name"
}

if (-not $BotName) {
    $BotName = Read-Host "Enter the Bot Service name (4-42 chars, alphanumeric and hyphens only)"
}

if (-not $BotDisplayName) {
    $BotDisplayName = $BotName
}

if (-not $MessagingEndpoint) {
    $MessagingEndpoint = Read-Host "Enter the Messaging Endpoint URL (e.g., https://your-app.azurewebsites.net/api/messages)"
}

# Validate required parameters
if (-not $TenantId -or -not $AgentBlueprintAppId -or -not $ResourceGroup -or -not $BotName -or -not $MessagingEndpoint) {
    Write-Error "Missing required parameters. Please provide TenantId, AgentBlueprintAppId, ResourceGroup, BotName, and MessagingEndpoint."
    exit 1
}

Write-Host ""
Write-Host "=== Azure Bot Service Creation ===" -ForegroundColor Green
Write-Host "Tenant ID:            $TenantId"
Write-Host "Agent Blueprint ID:   $AgentBlueprintAppId"
Write-Host "Resource Group:       $ResourceGroup"
Write-Host "Bot Name:             $BotName"
Write-Host "Display Name:         $BotDisplayName"
Write-Host "Messaging Endpoint:   $MessagingEndpoint"
Write-Host "SKU:                  $Sku"
Write-Host "Enable Teams:         $EnableTeamsChannel"
Write-Host ""

# Check if logged into Azure CLI
Write-Host "Checking Azure CLI login status..." -ForegroundColor Cyan
$azAccount = az account show 2>$null | ConvertFrom-Json
if (-not $azAccount) {
    Write-Host "Not logged into Azure CLI. Please run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "Logged in as: $($azAccount.user.name)" -ForegroundColor Green

# Check if bot already exists
Write-Host "Checking if bot '$BotName' already exists..." -ForegroundColor Cyan
$existingBot = az bot show --resource-group $ResourceGroup --name $BotName 2>$null | ConvertFrom-Json
if ($existingBot) {
    Write-Host "Bot '$BotName' already exists in resource group '$ResourceGroup'." -ForegroundColor Yellow
    Write-Host "  App ID: $($existingBot.properties.msaAppId)"
    Write-Host "  Endpoint: $($existingBot.properties.endpoint)"
    
    $update = Read-Host "Do you want to update the messaging endpoint? (y/n)"
    if ($update -eq "y") {
        Write-Host "Updating messaging endpoint..." -ForegroundColor Cyan
        az bot update --resource-group $ResourceGroup --name $BotName --endpoint $MessagingEndpoint | Out-Null
        Write-Host "Messaging endpoint updated." -ForegroundColor Green
    }
}
else {
    # Create the bot
    Write-Host "Creating Azure Bot Service '$BotName'..." -ForegroundColor Cyan
    
    $botResult = az bot create `
        --resource-group $ResourceGroup `
        --name $BotName `
        --app-type SingleTenant `
        --appid $AgentBlueprintAppId `
        --tenant-id $TenantId `
        --sku $Sku `
        --endpoint $MessagingEndpoint `
        --display-name $BotDisplayName `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create bot: $botResult"
        exit 1
    }
    
    $bot = $botResult | ConvertFrom-Json
    Write-Host "Bot created successfully!" -ForegroundColor Green
    Write-Host "  Resource ID: $($bot.id)"
    Write-Host "  App ID: $($bot.properties.msaAppId)"
    Write-Host "  Endpoint: $($bot.properties.endpoint)"
}

# Enable Teams channel if requested
if ($EnableTeamsChannel) {
    Write-Host ""
    Write-Host "Enabling Microsoft Teams channel..." -ForegroundColor Cyan
    
    # Check if Teams channel already exists
    $teamsChannel = az bot msteams show --resource-group $ResourceGroup --name $BotName 2>$null | ConvertFrom-Json
    if ($teamsChannel) {
        Write-Host "Teams channel is already enabled." -ForegroundColor Yellow
    }
    else {
        $teamsResult = az bot msteams create --resource-group $ResourceGroup --name $BotName 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to enable Teams channel: $teamsResult"
        }
        else {
            Write-Host "Teams channel enabled successfully!" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "=== Bot Service Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Navigate to: https://dev.teams.microsoft.com/tools/agent-blueprint"
Write-Host "2. Select your Agent Blueprint"
Write-Host "3. Go to Configuration"
Write-Host "4. Set Agent type = 'Bot based'"
Write-Host "5. Paste Bot App ID: $AgentBlueprintAppId"
Write-Host "6. Save"
Write-Host ""
