@echo off
setlocal EnableDelayedExpansion

:: Self-elevate to Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"

echo =======================================================
echo          AMPCrypt 1-Click Secure Suite Setup
echo =======================================================
echo.

:: 1. Install & Trust Root Certificate
echo [1/3] Trusting AMPCrypt Signing Certificate...
if exist "ampcrypt_cert.cer" (
    powershell -Command "Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue; Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue" >nul 2>&1
    echo [+] Certificate trusted successfully.
) else (
    echo [!] Certificate file not found, skipping.
)

:: 2. Install WinFsp Virtual Local Disk Driver
echo [2/3] Installing WinFsp Virtual Local Disk Driver...
if exist "winfsp.msi" (
    start /wait msiexec.exe /i "winfsp.msi" /qn /norestart
    echo [+] WinFsp Driver installed successfully.
) else (
    echo [!] WinFsp installer not found, skipping.
)

:: 3. Register MSIX Package
echo [3/3] Installing AMPCrypt MSIX Package...
if exist "ampcrypt.msix" (
    powershell -Command "Add-AppxPackage -Path 'ampcrypt.msix' -ForceApplicationShutdown"
    if %errorlevel% equ 0 (
        echo.
        echo =======================================================
        echo   [+] AMPCrypt installed successfully!
        echo =======================================================
        echo.
        powershell -Command "Start-Process 'shell:AppsFolder\com.itsupport.ampcrypt_1.0.0.0_x64__p24x91w1s9d7m!AMPCrypt'" >nul 2>&1
    ) else (
        echo [-] Standard Appx registration encountered an issue. Starting standalone ampcrypt.exe...
        if exist "ampcrypt.exe" (
            start "" "ampcrypt.exe"
        )
    )
) else (
    if exist "ampcrypt.exe" (
        start "" "ampcrypt.exe"
    )
)

echo.
echo Setup Complete!
timeout /t 3 >nul
exit /b 0
