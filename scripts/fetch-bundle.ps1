# Downloads one released bundle, checks its SHA-256, and unpacks it (the folder it creates is named "rizin").
# usage: fetch-bundle.ps1 -Tag bundle-rizin0.9.1-rzghidra0.9.0-r1 -Rid win-x64 -Dest Publish\win-x64
param([Parameter(Mandatory)][string]$Tag, [Parameter(Mandatory)][string]$Rid, [Parameter(Mandatory)][string]$Dest)
$ErrorActionPreference = 'Stop'
$name = "gdio-rizin-bundle-$($Tag -replace '^bundle-', '')-$Rid"
$base = "https://github.com/GameDriver-io/gdio.rizin-bundle/releases/download/$Tag"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null
Invoke-WebRequest -Uri "$base/$name.zip" -OutFile "$tmp\$name.zip"
Invoke-WebRequest -Uri "$base/$name.zip.sha256" -OutFile "$tmp\$name.zip.sha256"
$expected = ((Get-Content "$tmp\$name.zip.sha256" -Raw).Trim() -split '\s+')[0].ToLower()
if ((Get-FileHash "$tmp\$name.zip" -Algorithm SHA256).Hash.ToLower() -ne $expected) { throw "SHA-256 mismatch for $name.zip" }
New-Item -ItemType Directory -Force $Dest | Out-Null
if (Test-Path (Join-Path $Dest 'rizin')) { Remove-Item -Recurse -Force (Join-Path $Dest 'rizin') }
tar -xf "$tmp\$name.zip" -C $Dest
Remove-Item -Recurse -Force $tmp
"unpacked $name into $Dest\rizin"
