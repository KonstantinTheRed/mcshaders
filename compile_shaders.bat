@echo off
:: compile_shaders.bat — One-click shader compilation
:: Double-click this file or run from terminal

cd /d "%~dp0"

where python >nul 2>&1
if errorlevel 1 (
    echo ERROR: python not found in PATH
    echo Install Python from https://www.python.org/downloads/
    echo Make sure to check "Add to PATH" during install.
    echo.
    pause
    exit /b 1
)

set "VULKAN_SDK=C:\VulkanSDK\1.4.341.1"
python compile_shaders.py %*
echo.
pause
