$exe = "$env:SystemDrive\Navanta\Belarc Advisor\advisorinstaller.exe"
if (-not (Test-Path $exe)) {
    Write-Host "ERROR: Belarc installer not found at $exe" -ForegroundColor Red
    exit 1
}
Start-Process -FilePath $exe -Wait -ArgumentList '/S'
