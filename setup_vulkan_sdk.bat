@echo off
:: setup_vulkan_sdk.bat — Download and install the Vulkan SDK
:: Double-click this file to run. Will prompt for admin if needed.

cd /d "%~dp0"
echo === Vulkan SDK Setup ===
echo.

:: Check if already installed via common paths
if exist "C:\VulkanSDK" (
    for /f "delims=" %%d in ('dir /b /ad /o-n "C:\VulkanSDK" 2^>nul') do (
        if exist "C:\VulkanSDK\%%d\Bin\glslc.exe" (
            echo Found Vulkan SDK at: C:\VulkanSDK\%%d
            echo glslc: C:\VulkanSDK\%%d\Bin\glslc.exe
            echo.
            echo SDK already installed! You can run compile_shaders.bat now.
            echo.
            pause
            exit /b 0
        )
    )
)

:: Check PATH
where glslc >nul 2>&1
if %errorlevel% equ 0 (
    echo glslc found in PATH:
    where glslc
    echo.
    echo SDK already available! You can run compile_shaders.bat now.
    echo.
    pause
    exit /b 0
)

echo Vulkan SDK not found. Downloading installer...
echo.

set INSTALLER=%TEMP%\VulkanSDK-Installer.exe
set URL=https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-sdk.exe

echo URL: %URL%
echo Destination: %INSTALLER%
echo.

:: Download using curl (built into Windows 10+)
curl -L -o "%INSTALLER%" "%URL%"

if not exist "%INSTALLER%" (
    echo.
    echo Download failed. Please download manually from:
    echo   https://vulkan.lunarg.com/sdk/home#windows
    echo.
    echo Install with default settings, then run compile_shaders.bat
    echo.
    pause
    exit /b 1
)

echo.
echo Download complete! Launching installer...
echo.
echo   - Accept default install location (C:\VulkanSDK\%SDK_VERSION%)
echo   - Make sure "Shader Toolchain" is checked
echo   - Click Install
echo.

start /wait "" "%INSTALLER%"

:: Verify
if exist "C:\VulkanSDK\%SDK_VERSION%\Bin\glslc.exe" (
    echo.
    echo === Vulkan SDK installed successfully! ===
    echo glslc: C:\VulkanSDK\%SDK_VERSION%\Bin\glslc.exe
    echo.
    echo You can now run: compile_shaders.bat
) else (
    echo.
    echo Could not verify installation at the default path.
    echo Check C:\VulkanSDK\ to confirm, then run compile_shaders.bat
)

echo.
pause
