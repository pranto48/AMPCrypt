$cert = Get-Item "Cert:\CurrentUser\My\3C15B5EC122DD7E3DBE6028B66EFBC569558E226"

$store1 = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPeople", "CurrentUser")
$store1.Open("ReadWrite")
$store1.Add($cert)
$store1.Close()

Write-Host "Cert successfully added to CurrentUser\TrustedPeople" -ForegroundColor Green
