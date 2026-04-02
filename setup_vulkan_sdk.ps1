# setup_vulkan_sdk.ps1 — Download and install the Vulkan SDK (requires admin)
# Run: Right-click -> Run with PowerShell (as Administrator)

$ErrorActionPreference = "Stop"
$sdkVersion = "1.4.313.0"
$installerUrl = "https://sdk.lunarg.com/sdk/download/$sdkVersion/windows/VulkanSDK-$sdkVersion-Installer.exe"
$installerPath = "$env:TEMP\VulkanSDK-Installer.exe"

Write-Host "=== Vulkan SDK Setup ===" -ForegroundColor Cyan

# Check if already installed
$existingSDK = $env:VULKAN_SDK
if ($existingSDK -and (Test-Path "$existingSDK\Bin\glslc.exe")) {
    Write-Host "Vulkan SDK already installed at: $existingSDK" -ForegroundColor Green
    Write-Host "glslc found: $existingSDK\Bin\glslc.exe"
    exit 0
}

# Check common install paths
$commonPaths = Get-ChildItem "C:\VulkanSDK" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($commonPaths -and (Test-Path "$($commonPaths.FullName)\Bin\glslc.exe")) {
    Write-Host "Found existing SDK at: $($commonPaths.FullName)" -ForegroundColor Green
    Write-Host "Set VULKAN_SDK environment variable:"
    Write-Host "  [Environment]::SetEnvironmentVariable('VULKAN_SDK', '$($commonPaths.FullName)', 'User')"
    exit 0
}

Write-Host "Downloading Vulkan SDK $sdkVersion..." -ForegroundColor Yellow
Write-Host "URL: $installerUrl"

try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    Write-Host "Download complete: $installerPath" -ForegroundColor Green
} catch {
    Write-Host "Auto-download failed. Please download manually:" -ForegroundColor Red
    Write-Host "  https://vulkan.lunarg.com/sdk/home#windows" -ForegroundColor White
    Write-Host ""
    Write-Host "Install with default settings, then re-run compile_shaders.bat" -ForegroundColor White
    exit 1
}

Write-Host "Launching installer..." -ForegroundColor Yellow
Write-Host "  - Accept defaults"
Write-Host "  - Ensure 'Shader Toolchain' component is checked"
Write-Host ""
Start-Process -FilePath $installerPath -Wait

# Verify installation
$env:VULKAN_SDK = "C:\VulkanSDK\$sdkVersion"
if (Test-Path "$env:VULKAN_SDK\Bin\glslc.exe") {
    Write-Host ""
    Write-Host "=== Vulkan SDK installed successfully ===" -ForegroundColor Green
    Write-Host "glslc: $env:VULKAN_SDK\Bin\glslc.exe"
    Write-Host ""
    Write-Host "You can now run: compile_shaders.bat" -ForegroundColor Cyan
} else {
    Write-Host "Installation may have used a different path." -ForegroundColor Yellow
    Write-Host "Check C:\VulkanSDK\ and set VULKAN_SDK manually if needed."
}
