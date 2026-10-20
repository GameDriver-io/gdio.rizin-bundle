# Builds the rizin + rz-ghidra bundle for win-x64.
# rizin is rizin's own prebuilt Windows package (headers, import libraries and DLLs included), pinned by hash in VERSIONS;
# rz-ghidra is built from the pinned tag against it with MSVC. The result is self-tested from a moved folder with a
# space in its path, and zipped.
# Needs: an MSVC environment (run from a Developer PowerShell, or the workflow's msvc-dev-cmd step), cmake, ninja, git.
param([string]$Work = (Join-Path $PSScriptRoot '..\work\win-x64'), [string]$Out = (Join-Path $PSScriptRoot '..\dist'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

# Windows' own tar (bsdtar): on the CI runners a bare "tar" can be Git's GNU tar, which reads "D:\..." as a remote host. Every call has a time limit,
# so a hang fails the build with its name instead of waiting for the job to time out.
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $tar)) { throw "missing tool: $tar" }
function Invoke-Tar([string[]]$TarArgs, [int]$TimeoutSeconds = 300) {
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] tar $($TarArgs -join ' ')"
    $psi = [Diagnostics.ProcessStartInfo]::new($tar)
    foreach ($a in $TarArgs) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) { $proc.Kill($true); throw "tar did not finish within $TimeoutSeconds s: $($TarArgs -join ' ')" }
    if ($proc.ExitCode) { throw "tar failed (exit $($proc.ExitCode)): $($TarArgs -join ' ')" }
}

$v = @{}
Get-Content (Join-Path $root 'VERSIONS') | Where-Object { $_ -match '^[A-Z_0-9]+=' } | ForEach-Object { $k, $val = $_ -split '=', 2; $v[$k] = $val.Trim() }
$rid = 'win-x64'
$name = "gdio-rizin-bundle-rizin$($v.RIZIN_VERSION)-rzghidra$($v.RZ_GHIDRA_VERSION)-r$($v.BUNDLE_REVISION)-$rid"

foreach ($tool in 'cl', 'cmake', 'ninja', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "missing tool: $tool (cl needs an MSVC developer environment)" }
}
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force $Work, $Out | Out-Null
$Work = (Resolve-Path $Work).Path; $Out = (Resolve-Path $Out).Path
$stage = Join-Path $Work 'stage\rizin'

Write-Host "== rizin $($v.RIZIN_VERSION) (prebuilt)"
$zip = Join-Path $Work 'rizin-win.zip'
Invoke-WebRequest -Uri $v.RIZIN_WIN_URL -OutFile $zip
if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLower() -ne $v.RIZIN_WIN_SHA256) { throw 'the downloaded rizin package does not match the pinned SHA-256' }
Expand-Archive $zip -DestinationPath (Join-Path $Work 'rizin-extract')
$top = Get-ChildItem (Join-Path $Work 'rizin-extract') -Directory | Select-Object -First 1
New-Item -ItemType Directory -Force (Split-Path $stage) | Out-Null
Move-Item $top.FullName $stage

Write-Host "== rz-ghidra $($v.RZ_GHIDRA_TAG)"
$rzSrc = Join-Path $Work 'rz-ghidra'
git clone --quiet --depth 1 --branch $v.RZ_GHIDRA_TAG --recurse-submodules --shallow-submodules https://github.com/rizinorg/rz-ghidra $rzSrc
if ($LASTEXITCODE) { throw 'git clone failed' }
if ((git -C $rzSrc rev-parse HEAD) -ne $v.RZ_GHIDRA_COMMIT) { throw "rz-ghidra $($v.RZ_GHIDRA_TAG) is not commit $($v.RZ_GHIDRA_COMMIT)" }
$build = Join-Path $Work 'rz-ghidra-build'
# Windows has no system zlib, which rz-ghidra asks for by default: have it fetch and build its own (a pinned zlib 1.3.1).
# The plugin folder is given relative and the prefix with forward slashes: rz-ghidra bakes "<prefix>/<plugin folder>/rz_ghidra_sleigh" into the plugin
# as a C string, and rizin's own plugin folder setting has backslashes (\r, \p ...) that the compiler reads as escape sequences. TA points the plugin at
# its Sleigh data with SLEIGHHOME at run time anyway, so the baked path only has to compile.
# Only the decompiler plugin (core_ghidra, the pdg command) is built. The optional asm/analysis plugins do not link on Windows (they need symbols the
# decompiler plugin does not export), and rz-ghidra's own Windows CI turns them off too.
$stageFwd = $stage.Replace('\', '/')
cmake -S $rzSrc -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$stageFwd" "-DCMAKE_INSTALL_PREFIX=$stageFwd" -DRIZIN_INSTALL_PLUGDIR=lib/rizin/plugins -DUSE_SYSTEM_ZLIB=OFF -DBUILD_SLEIGH_PLUGIN=OFF -DBUILD_CUTTER_PLUGIN=OFF
if ($LASTEXITCODE) { throw 'cmake configure failed' }
# Keep going after a failure (-k 0) so one run shows every error, log it, and on failure print just the errors: the compiler's
# own message is lines above ninja's final "build stopped", buried in warnings.
$buildLog = Join-Path $Work 'rz-ghidra-build.log'
cmake --build $build -- -k 0 2>&1 | Tee-Object -FilePath $buildLog | Out-Host
if ($LASTEXITCODE) {
    Write-Host '=============== the build failed: first errors ==============='
    Select-String -Path $buildLog -Pattern 'FAILED:', ' error C\d+', 'fatal error', ' error LNK\d+', 'CMake Error' -Context 0, 3 |
        Select-Object -First 30 | ForEach-Object { $_.ToString() }
    Write-Host '=============================================================='
    throw 'cmake build failed'
}
cmake --install $build
if ($LASTEXITCODE) { throw 'cmake install failed' }

Write-Host '== trimming to what Test Assistant runs'
foreach ($p in 'include', 'lib\cmake', 'lib\pkgconfig', 'share\man', 'share\doc') { Remove-Item -Recurse -Force (Join-Path $stage $p) -ErrorAction SilentlyContinue }
Get-ChildItem (Join-Path $stage 'lib') -Filter *.lib -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem (Join-Path $stage 'bin') -Filter *.exe | Where-Object { $_.Name -ne 'rizin.exe' } | Remove-Item -Force

Write-Host '== licences and manifest'
$lic = Join-Path $stage 'licenses'; New-Item -ItemType Directory -Force $lic | Out-Null
foreach ($f in Get-ChildItem $rzSrc -File | Where-Object { $_.Name -match '^(COPYING|LICENSE|NOTICE)' }) { Copy-Item $f.FullName (Join-Path $lic "rz-ghidra-$($f.Name)") }
# rizin's licence texts, taken from its pinned tag (the same two files the macOS bundle carries). The source tarball is not unpacked here: tar never
# finished extracting it on the Windows runner.
$ProgressPreference = 'SilentlyContinue'
foreach ($f in 'COPYING', 'COPYING.LESSER') {
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] rizin $f"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/rizinorg/rizin/v$($v.RIZIN_VERSION)/$f" -OutFile (Join-Path $lic "rizin-v$($v.RIZIN_VERSION)-$f") -TimeoutSec 120
}

$pluginFile = Get-ChildItem $stage -Recurse -Filter 'core_ghidra.dll' | Select-Object -First 1
if (-not $pluginFile) { throw 'the rz-ghidra plugin was not installed' }
$pluginsRel = [IO.Path]::GetRelativePath($stage, $pluginFile.DirectoryName).Replace('\', '/')
@{
    name = $name; rid = $rid; rizin = $v.RIZIN_VERSION; rzGhidra = $v.RZ_GHIDRA_VERSION; rzGhidraCommit = $v.RZ_GHIDRA_COMMIT
    rizinExecutable = 'bin/rizin.exe'; pluginsDirectory = $pluginsRel; sleighDirectory = "$pluginsRel/rz_ghidra_sleigh"
    gplCodeIncluded = $null; note = "rizin is rizin's own prebuilt package, whose GPL setting is rizin's default"
    source = 'https://github.com/GameDriver-io/gdio.rizin-bundle'
} | ConvertTo-Json | Set-Content (Join-Path $stage 'BUNDLE.json') -Encoding UTF8

Write-Host '== self-test (moved folder, path with a space)'
& (Join-Path $PSScriptRoot 'selftest.ps1') -Src $stage -Expected $v.RIZIN_VERSION

Write-Host '== zip'
$zipOut = Join-Path $Out "$name.zip"
if (Test-Path $zipOut) { Remove-Item $zipOut }
Invoke-Tar @('-a', '-c', '-f', $zipOut, '-C', (Split-Path $stage), 'rizin')
"$((Get-FileHash $zipOut -Algorithm SHA256).Hash.ToLower())  $name.zip" | Set-Content "$zipOut.sha256" -Encoding ASCII
"built $zipOut ($([math]::Round((Get-Item $zipOut).Length / 1MB, 1)) MB)"

Write-Host '== self-test of the unzipped result'
$check = Join-Path $Work 'unzipped'; New-Item -ItemType Directory -Force $check | Out-Null
Invoke-Tar @('-xf', $zipOut, '-C', $check)
& (Join-Path $PSScriptRoot 'selftest.ps1') -Src (Join-Path $check 'rizin') -Expected $v.RIZIN_VERSION
