# Windows twin of selftest.sh: proves a staged bundle works after being moved to a folder with a space in its path,
# running the decompiler on a known ARM64 function the way Test Assistant does (RZ_LIB_PLUGINS + SLEIGHHOME).
# usage: selftest.ps1 -Src <bundle root: the folder that contains bin\ and lib\> -Expected <rizin version>
param([Parameter(Mandatory)][string]$Src, [Parameter(Mandatory)][string]$Expected)
$ErrorActionPreference = 'Stop'

# Runs rizin with a time limit and a closed stdin, so a hang fails the self-test with its output instead of waiting for the job to time out.
function Invoke-Rizin([string]$Exe, [string[]]$Arguments, [hashtable]$Environment = @{}, [int]$TimeoutSeconds = 180) {
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    foreach ($k in $Environment.Keys) { $psi.Environment[$k] = $Environment[$k] }
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    $proc = [Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEndAsync(); $stderr = $proc.StandardError.ReadToEndAsync()
    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        $proc.Kill($true)
        throw "SELFTEST FAILED: rizin did not finish within $TimeoutSeconds s (args: $($Arguments -join ' '))"
    }
    $proc.WaitForExit()
    [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = ($stdout.Result + $stderr.Result) }
}
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rzself ' + [guid]::NewGuid().ToString('N'))
$dest = Join-Path $tmp 'moved bundle\rizin'
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $Src '*') $dest -Recurse

$plugin = Get-ChildItem $dest -Recurse -Filter 'core_ghidra.dll' | Select-Object -First 1
if (-not $plugin) { throw 'SELFTEST FAILED: no core_ghidra plugin in the bundle' }
$plugins = $plugin.DirectoryName
$sleigh = Join-Path $plugins 'rz_ghidra_sleigh'
if (-not (Test-Path $sleigh)) { throw 'SELFTEST FAILED: no rz_ghidra_sleigh folder next to the plugin' }
$rizin = Join-Path $dest 'bin\rizin.exe'

$vr = Invoke-Rizin $rizin @('-v') @{} 60
$version = ($vr.Output -split "`r?`n" | Select-Object -First 1)
"rizin: $version (exit $($vr.ExitCode))"
if ($version -notmatch [regex]::Escape($Expected)) { throw "SELFTEST FAILED: expected rizin $Expected" }

# ldr x0, [x0, #0xe0] ; ret   mapped at 0x4000
$r = Invoke-Rizin $rizin @('-N', '-q', '-a', 'arm', '-b', '64', '-e', 'scr.color=0', '-e', 'analysis.in=io.maps', '-m', '0x4000', '-c', 'wx 007040f9c0035fd6 @ 0x4000; s 0x4000; af; pdg', 'malloc://64') @{ RZ_LIB_PLUGINS = $plugins; SLEIGHHOME = $sleigh } 180
$out = $r.Output
"rizin pdg exit code: $($r.ExitCode)"
$out
if ($out -notmatch '0xe0') { throw 'SELFTEST FAILED: the decompiled output does not contain the expected offset 0xe0' }
if ($out -notmatch 'return') { throw 'SELFTEST FAILED: the decompiled output has no return statement' }
if ($out -match '(?i)no sleigh specification') { throw 'SELFTEST FAILED: the plugin could not find its Sleigh data' }
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
"SELFTEST OK ($plugins)"
