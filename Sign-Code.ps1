[CmdletBinding()]
param(
    [string]$SigningTarget,
    [string]$CertSearchString
)
If ($null -ne $CertSearchString) {
    $SigningCert = Get-ChildItem cert:\currentuser\my -CodeSigningCert | Where-Object { ($_.subject -match $CertSearchString) -or ($_.FriendlyName -match $CertSearchString) }
}
ElseIf ($null -eq $CertSearchString) {
    $SigningCert = Get-ChildItem cert:\currentuser\my -CodeSigningCert
}
If ($SigningCert.count -gt "1") {
    Write-Host "Multiple signing certificates available, please select:"
    $CertIterator = 0
    foreach ($CertCandidate in $SigningCert) {
        $SelectorTextFN = $CertCandidate.FriendlyName
        $SelectorTextSub = $CertCandidate.Subject
        Write-Host "Certificate #"$CertIterator -ForegroundColor Blue
        Write-Host `t"Friendly Name: "$SelectorTextFN -ForegroundColor Cyan
        Write-Host `t"      Subject: "$SelectorTextSub -ForegroundColor Cyan
        $CertIterator = 1+$CertIterator
    }
$CertSelection = Read-Host "Select Cert" 
$SigningCert = $SigningCert[($CertSelection)]
}
Set-AuthenticodeSignature -FilePath $SigningTarget -Certificate $SigningCert -TimestampServer "http://timestamp.digicert.com"
Start-Sleep -s 1