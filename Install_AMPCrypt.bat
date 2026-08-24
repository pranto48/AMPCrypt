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
echo [1/4] Trusting AMPCrypt Signing Certificate...
powershell -ExecutionPolicy Bypass -Command "
try {
    if (Test-Path 'ampcrypt_cert.cer') {
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
        Import-Certificate -FilePath 'ampcrypt_cert.cer' -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
    }
    if (Test-Path 'ampcrypt.msix') {
        `$sig = (Get-AuthenticodeSignature 'ampcrypt.msix').SignerCertificate
        if (`$sig) {
            `$tempCer = [System.IO.Path]::GetTempFileName() + '.cer'
            [System.IO.File]::WriteAllBytes(`$tempCer, `$sig.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction SilentlyContinue | Out-Null
            Import-Certificate -FilePath `$tempCer -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' -ErrorAction SilentlyContinue | Out-Null
            Remove-Item `$tempCer -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host '[+] AMPCrypt Certificate trusted successfully in Windows Root store.' -ForegroundColor Green
} catch {
    Write-Host '[!] Certificate trust note: ' `$_.Exception.Message
}
"

:: 2. Deploy Local Virtual Filesystem Driver & Helper
echo [2/4] Deploying Local Virtual Filesystem Helper...
powershell -ExecutionPolicy Bypass -Command "
`$supportDir = Join-Path `$env:LOCALAPPDATA 'com.itsupport.ampcrypt';
if (!(Test-Path `$supportDir)) { New-Item -ItemType Directory -Path `$supportDir -Force | Out-Null }
if (Test-Path 'rclone.exe') {
    Copy-Item 'rclone.exe' -Destination (Join-Path `$supportDir 'rclone.exe') -Force
}
`$progFiles = Join-Path (Get-Item env:ProgramFiles).Value 'ampcrypt';
if (!(Test-Path `$progFiles)) { New-Item -ItemType Directory -Path `$progFiles -Force | Out-Null }
if (Test-Path 'rclone.exe') {
    Copy-Item 'rclone.exe' -Destination (Join-Path `$progFiles 'rclone.exe') -Force
}
Write-Host '[+] Filesystem helpers initialized successfully.' -ForegroundColor Green
"

:: 3. Install WinFsp Virtual Local Disk Driver
echo [3/4] Installing WinFsp Virtual Local Disk Driver...
if exist "winfsp.msi" (
    start /wait msiexec.exe /i "winfsp.msi" /qn /norestart
    echo [+] WinFsp Driver installed successfully.
) else (
    echo [!] WinFsp installer not found in current folder, checking system...
)

:: 4. Register MSIX Package
echo [4/4] Installing AMPCrypt MSIX Package...
if exist "ampcrypt.msix" (
    powershell -ExecutionPolicy Bypass -Command "Add-AppxPackage -Path 'ampcrypt.msix' -ForceApplicationShutdown"
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
timeout /t 4 >nul
exit /b 0
