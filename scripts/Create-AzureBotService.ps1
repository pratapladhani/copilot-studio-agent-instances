<#
.SYNOPSIS
Creates an Azure Bot Service resource and configures it for Agent User messaging.

.DESCRIPTION
This script:
1. Creates an Azure Bot Service resource using the Agent Blueprint App ID
2. Configures the messaging endpoint (dev tunnel or production URL)
3. Enables the Microsoft Teams channel
4. Configures the Agent Blueprint for bot-based notifications

.PARAMETER ConfigFile
Path to a JSON configuration file containing required parameters.

.PARAMETER TenantId
The Tenant ID (required if not using ConfigFile).

.PARAMETER AgentBlueprintAppId
The Agent Blueprint Application ID (required if not using ConfigFile).

.PARAMETER BotHandle
A globally unique name for the bot (required if not using ConfigFile).

.PARAMETER MessagingEndpoint
The messaging endpoint URL (e.g., https://your-tunnel.devtunnels.ms/api/messages).

.PARAMETER ResourceGroup
The Azure Resource Group name. Will be created if it doesn't exist.

.PARAMETER Location
The Azure region for the bot resource (default: westus2).

.PARAMETER SkipTeamsChannel
Skip enabling the Microsoft Teams channel.

.EXAMPLE
.\Create-AzureBotService.ps1 -ConfigFile ".\budget-advisor-user-config.json" -MessagingEndpoint "https://wpkqt4b0-3978.usw2.devtunnels.ms/api/messages"

.EXAMPLE
.\Create-AzureBotService.ps1 -TenantId "xxx" -AgentBlueprintAppId "xxx" -BotHandle "my-agent-bot" -MessagingEndpoint "https://xxx/api/messages"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $false)]
    [string]$AgentBlueprintAppId,
    
    [Parameter(Mandatory = $false)]
    [string]$BotHandle,
    
    [Parameter(Mandatory = $false)]
    [string]$MessagingEndpoint,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-agent-bots",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "westus2",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipTeamsChannel
)

# Display script header
Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host "                           Azure Bot Service Creation Script                                    " -ForegroundColor Cyan
Write-Host "================================================================================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Reading configuration from file: $ConfigFile" -ForegroundColor Blue
    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json
        $TenantId = $config.TenantId
        $AgentBlueprintAppId = $config.AgentBlueprintId
        
        # Generate bot handle from config file name if not provided
        if (-not $BotHandle) {
            $configName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigFile)
            $BotHandle = $configName -replace "-user-config", "-bot" -replace "_", "-"
        }
        
        Write-Host "  • Tenant ID: $TenantId" -ForegroundColor Gray
        Write-Host "  • Blueprint App ID: $AgentBlueprintAppId" -ForegroundColor Gray
        Write-Host "  • Bot Handle: $BotHandle" -ForegroundColor Gray
    }
    catch {
        Write-Host "ERROR: Failed to read configuration file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Validate required parameters
if (-not $TenantId -or -not $AgentBlueprintAppId) {
    Write-Host "ERROR: TenantId and AgentBlueprintAppId are required." -ForegroundColor Red
    Write-Host "  Either provide -ConfigFile or specify -TenantId and -AgentBlueprintAppId" -ForegroundColor Yellow
    exit 1
}

if (-not $BotHandle) {
    Write-Host "ERROR: BotHandle is required. Provide a globally unique name for your bot." -ForegroundColor Red
    exit 1
}

if (-not $MessagingEndpoint) {
    Write-Host "WARNING: MessagingEndpoint not provided. You'll need to configure it manually later." -ForegroundColor Yellow
    $MessagingEndpoint = "https://your-endpoint/api/messages"
}

# Check for Azure CLI
Write-Host ""
Write-Host "Step 1: Checking prerequisites..." -ForegroundColor Yellow

$azVersion = az version 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $azVersion) {
    Write-Host "ERROR: Azure CLI is not installed or not in PATH." -ForegroundColor Red
    Write-Host "  Install from: https://docs.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Yellow
    exit 1
}
Write-Host "  ✓ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green

# Login to Azure
Write-Host ""
Write-Host "Step 2: Logging into Azure..." -ForegroundColor Yellow

$account = az account show 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $account) {
    Write-Host "  Not logged in. Initiating login..." -ForegroundColor Gray
    az login --tenant $TenantId
    $account = az account show | ConvertFrom-Json
}

if ($account.tenantId -ne $TenantId) {
    Write-Host "  Switching to tenant: $TenantId" -ForegroundColor Gray
    az login --tenant $TenantId
}

Write-Host "  ✓ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "  ✓ Subscription: $($account.name)" -ForegroundColor Green

# Create or verify resource group
Write-Host ""
Write-Host "Step 3: Creating/verifying resource group..." -ForegroundColor Yellow

$rgExists = az group exists --name $ResourceGroup | ConvertFrom-Json
if (-not $rgExists) {
    Write-Host "  Creating resource group: $ResourceGroup in $Location" -ForegroundColor Gray
    az group create --name $ResourceGroup --location $Location | Out-Null
    Write-Host "  ✓ Resource group created" -ForegroundColor Green
}
else {
    Write-Host "  ✓ Resource group already exists" -ForegroundColor Green
}

# Check if bot already exists
Write-Host ""
Write-Host "Step 4: Creating Azure Bot resource..." -ForegroundColor Yellow

$existingBot = az bot show --name $BotHandle --resource-group $ResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue

if ($existingBot) {
    Write-Host "  Bot '$BotHandle' already exists. Updating configuration..." -ForegroundColor Yellow
}
else {
    Write-Host "  Creating bot: $BotHandle" -ForegroundColor Gray
    Write-Host "  Using App ID: $AgentBlueprintAppId" -ForegroundColor Gray
    Write-Host "  Messaging Endpoint: $MessagingEndpoint" -ForegroundColor Gray
    
    # Create the Azure Bot
    # Note: We use --app-type SingleTenant for Agent Blueprints
    $createResult = az bot create `
        --resource-group $ResourceGroup `
        --name $BotHandle `
        --app-type SingleTenant `
        --appid $AgentBlueprintAppId `
        --tenant-id $TenantId `
        --endpoint $MessagingEndpoint `
        --sku F0 `
        2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to create bot: $createResult" -ForegroundColor Red
        Write-Host ""
        Write-Host "Alternative: Create manually via Azure Portal:" -ForegroundColor Yellow
        Write-Host "  1. Go to: https://portal.azure.com/#create/Microsoft.AzureBot" -ForegroundColor Gray
        Write-Host "  2. Bot handle: $BotHandle" -ForegroundColor Gray
        Write-Host "  3. Type of App: Single-tenant" -ForegroundColor Gray
        Write-Host "  4. App ID: $AgentBlueprintAppId (Use existing)" -ForegroundColor Gray
        Write-Host "  5. Tenant ID: $TenantId" -ForegroundColor Gray
        Write-Host "  6. Messaging endpoint: $MessagingEndpoint" -ForegroundColor Gray
        exit 1
    }
    
    Write-Host "  ✓ Azure Bot created successfully" -ForegroundColor Green
}

# Update messaging endpoint (in case it changed)
Write-Host ""
Write-Host "Step 5: Configuring messaging endpoint..." -ForegroundColor Yellow
Write-Host "  Endpoint: $MessagingEndpoint" -ForegroundColor Gray

az bot update `
    --resource-group $ResourceGroup `
    --name $BotHandle `
    --endpoint $MessagingEndpoint `
    2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Messaging endpoint configured" -ForegroundColor Green
}
else {
    Write-Host "  ⚠ Could not update endpoint via CLI. Update manually in Azure Portal." -ForegroundColor Yellow
}

# Enable Teams channel
if (-not $SkipTeamsChannel) {
    Write-Host ""
    Write-Host "Step 6: Enabling Microsoft Teams channel..." -ForegroundColor Yellow
    
    $teamsChannel = az bot msteams show --name $BotHandle --resource-group $ResourceGroup 2>$null
    
    if ($teamsChannel) {
        Write-Host "  ✓ Teams channel already enabled" -ForegroundColor Green
    }
    else {
        $channelResult = az bot msteams create `
            --name $BotHandle `
            --resource-group $ResourceGroup `
            2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Teams channel enabled" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠ Could not enable Teams channel via CLI." -ForegroundColor Yellow
            Write-Host "    Enable manually: Azure Portal → Bot → Channels → Microsoft Teams" -ForegroundColor Gray
        }
    }
}

# Configure Agent Blueprint notifications
Write-Host ""
Write-Host "Step 7: Configuring Agent Blueprint for bot notifications..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  ⚠ This step requires manual configuration:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. Go to: https://dev.teams.microsoft.com/tools/agent-blueprint" -ForegroundColor Cyan
Write-Host "  2. Select your Agent Blueprint" -ForegroundColor Gray
Write-Host "  3. Navigate to Configuration" -ForegroundColor Gray
Write-Host "  4. Select 'Bot based' for Agent type" -ForegroundColor Gray
Write-Host "  5. Paste App ID: $AgentBlueprintAppId" -ForegroundColor Gray
Write-Host "  6. Click Save" -ForegroundColor Gray
Write-Host ""

# Update config file with bot info
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    Write-Host "Step 8: Updating config file with bot information..." -ForegroundColor Yellow
    try {
        $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        
        # Add bot info if not present
        if (-not $config.PSObject.Properties['BotHandle']) {
            $config | Add-Member -NotePropertyName 'BotHandle' -NotePropertyValue $BotHandle -Force
        }
        else {
            $config.BotHandle = $BotHandle
        }
        
        if (-not $config.PSObject.Properties['MessagingEndpoint']) {
            $config | Add-Member -NotePropertyName 'MessagingEndpoint' -NotePropertyValue $MessagingEndpoint -Force
        }
        else {
            $config.MessagingEndpoint = $MessagingEndpoint
        }
        
        if (-not $config.PSObject.Properties['ResourceGroup']) {
            $config | Add-Member -NotePropertyName 'ResourceGroup' -NotePropertyValue $ResourceGroup -Force
        }
        else {
            $config.ResourceGroup = $ResourceGroup
        }
        
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        Write-Host "  ✓ Config file updated" -ForegroundColor Green
    }
    catch {
        Write-Host "  ⚠ Could not update config file: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Display summary
Write-Host ""
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host "                              AZURE BOT SERVICE SETUP COMPLETE                                  " -ForegroundColor Green
Write-Host "================================================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  • Bot Handle: $BotHandle" -ForegroundColor Gray
Write-Host "  • Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host "  • App ID: $AgentBlueprintAppId" -ForegroundColor Gray
Write-Host "  • Messaging Endpoint: $MessagingEndpoint" -ForegroundColor Gray
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  1. Configure Agent Blueprint at: https://dev.teams.microsoft.com/tools/agent-blueprint" -ForegroundColor Gray
Write-Host "  2. Ensure your relay service is running at the messaging endpoint" -ForegroundColor Gray
Write-Host "  3. Test by sending a message to your Agent User in Teams" -ForegroundColor Gray
Write-Host ""
Write-Host "Azure Portal Bot URL:" -ForegroundColor Cyan
Write-Host "  https://portal.azure.com/#@$TenantId/resource/subscriptions/$($account.id)/resourceGroups/$ResourceGroup/providers/Microsoft.BotService/botServices/$BotHandle/overview" -ForegroundColor Gray
Write-Host ""
