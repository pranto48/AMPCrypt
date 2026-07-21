# Self-signed certificate generator for AMPCrypt MSIX
$ErrorActionPreference = "Stop"

Write-Host "Creating & Trusting AMPCrypt Certificate..." -ForegroundColor Cyan

# 1. Create Self-Signed Code Signing Certificate under CurrentUser\My
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject "CN=IT Support BD, O=IT Support BD, L=Dhaka, S=Dhaka, C=BD" `
    -KeyUsage DigitalSignature `
    -FriendlyName "AMPCrypt Code Signing" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}") `
    -NotAfter (Get-Date).AddYears(10)

# 2. Add to CurrentUser\TrustedPeople (No Admin / No Security Popups required)
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "CurrentUser")
$store.Open("ReadWrite")
$store.Add($cert)
$store.Close()

Write-Host "Certificate installed to CurrentUser\TrustedPeople with Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

# 3. Export to PFX file for flutter msix builder
$pfxPath = "F:\OneDrive - arifmahmud\SynologyDrive\Website\Antigravity\AMPCrypt\ampcrypt_cert.pfx"
$password = ConvertTo-SecureString -String "AMPCrypt2024!" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null
Write-Host "PFX saved to $pfxPath" -ForegroundColor Green

# 4. Find signtool and sign the built MSIX
$msixPath = "F:\OneDrive - arifmahmud\SynologyDrive\Website\Antigravity\AMPCrypt\build\windows\x64\runner\Release\ampcrypt.msix"

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*x64*" } |
    Select-Object -First 1 -ExpandProperty FullName

if ($signtool -and (Test-Path $msixPath)) {
    Write-Host "Signing $msixPath using $signtool..." -ForegroundColor Cyan
    & $signtool sign /fd SHA256 /a /f $pfxPath /p "AMPCrypt2024!" $msixPath
    Write-Host "MSIX successfully signed!" -ForegroundColor Green
} else {
    Write-Host "MSIX re-sign skipped (signtool or msix file not found)." -ForegroundColor Yellow
}
