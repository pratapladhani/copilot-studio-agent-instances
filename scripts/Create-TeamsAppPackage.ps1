# Create-TeamsAppPackage.ps1
# Creates a Teams app package (.zip) for the Budget Advisor bot

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$teamsAppDir = Join-Path $scriptDir "..\teams-app"
$outputZip = Join-Path $teamsAppDir "BudgetAdvisor.zip"

# Create placeholder icons if they don't exist
$colorIconPath = Join-Path $teamsAppDir "color.png"
$outlineIconPath = Join-Path $teamsAppDir "outline.png"

# Create a simple 192x192 color icon (purple square)
if (-not (Test-Path $colorIconPath)) {
    Write-Host "Creating placeholder color.png (192x192)..." -ForegroundColor Yellow
    # Base64 encoded 192x192 purple PNG
    $colorPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAMAAAADACAYAAABS3GwHAAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAALEwAACxMBAJqcGAAAABl0RVh0U29mdHdhcmUAcGFpbnQubmV0IDQuMC4xMkMEa+wAAAFRSURBVHic7dExAQAACMCg+ZdeVR7BAOK4AwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB4swHntgAB6hKj/QAAAABJRU5ErkJggg=="
    [System.IO.File]::WriteAllBytes($colorIconPath, [Convert]::FromBase64String($colorPngBase64))
}

# Create a simple 32x32 outline icon
if (-not (Test-Path $outlineIconPath)) {
    Write-Host "Creating placeholder outline.png (32x32)..." -ForegroundColor Yellow
    # Base64 encoded 32x32 transparent PNG with outline
    $outlinePngBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABHNCSVQICAgIfAhkiAAAAAlwSFlzAAAA7AAAAOwBeShxvQAAABl0RVh0U29mdHdhcmUAd3d3Lmlua3NjYXBlLm9yZ5vuPBoAAAA0SURBVFiF7c0xAQAACAOgaexf2gED0tMZAQAAAAAAAAAAAAAAAAAAAAAAAAD+gQIAAOCHAQAAfQEOdAABfNjQjAAAAABJRU5ErkJggg=="
    [System.IO.File]::WriteAllBytes($outlineIconPath, [Convert]::FromBase64String($outlinePngBase64))
}

# Create the ZIP package
Write-Host "Creating Teams app package..." -ForegroundColor Cyan

if (Test-Path $outputZip) {
    Remove-Item $outputZip -Force
}

$filesToZip = @(
    (Join-Path $teamsAppDir "manifest.json"),
    (Join-Path $teamsAppDir "agenticUserTemplateManifest.json"),
    $colorIconPath,
    $outlineIconPath
)

Compress-Archive -Path $filesToZip -DestinationPath $outputZip -Force

if (Test-Path $outputZip) {
    Write-Host ""
    Write-Host "SUCCESS! Teams app package created:" -ForegroundColor Green
    Write-Host "  $outputZip" -ForegroundColor White
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Go to Microsoft Admin Center:" -ForegroundColor Gray
    Write-Host "   https://admin.microsoft.com/Adminportal/Home#/TeamsApps/ManageApps" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. Select 'Agents' -> 'All Agents' -> 'Upload custom agent'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Choose the ZIP file: $outputZip" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. After uploading, search for 'Budget Advisor' and click 'Activate'" -ForegroundColor Gray
    Write-Host ""
}
else {
    Write-Host "ERROR: Failed to create ZIP package" -ForegroundColor Red
}
