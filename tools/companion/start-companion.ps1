# tools/companion/start-companion.ps1 (C-9, WKE-559)
#
# What the logon task runs: bring the fork's dev server up if nothing is
# answering it, then start the companion's watcher. Nothing here is Lootpath
# logic - it is the two commands the owner has been typing into two PowerShell
# windows since 2026-09-08, in one place that survives a reboot.
#
#   .\start-companion.ps1              start the fork if needed, then watch
#   .\start-companion.ps1 -NoFork      never start the fork; just watch
#   .\start-companion.ps1 -Config c.json  a different companion config
#
# The two rules it keeps:
#   * never two watchers. The companion itself refuses on its lock file
#     (lib/lock.js); this checks first so the reason is one line rather than an
#     exit code, and so a logon that fires twice costs nothing.
#   * never a second dev server. The fork is started only when the configured
#     URL does not answer, which is the same test lib/fork.js makes.
[CmdletBinding()]
param(
    [string]$Config,
    [switch]$NoFork
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Line([string]$message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $message)
}

# The companion's own config, with the defaults lib/config.js ships. Only the
# three keys this script needs are read; everything else is the companion's.
function Get-CompanionConfig([string]$path) {
    $settings = @{
        forkPath                = 'c:\Code\qe-live-fork'
        forkUrl                 = 'http://localhost:3000'
        startFork               = $true
        forkStartTimeoutSeconds = 180
    }
    if (-not $path) { $path = Join-Path $here 'config.json' }
    if (Test-Path -LiteralPath $path) {
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach ($key in @($settings.Keys)) {
            if ($null -ne $json.PSObject.Properties[$key]) { $settings[$key] = $json.$key }
        }
        Write-Line "config $path"
    } else {
        Write-Line "no config at $path; using the built-in defaults"
    }
    return $settings
}

# Is anything listening where the fork should be? A TCP connect, not an HTTP
# request: a dev server that is still compiling answers the socket long before
# it answers a page, and the companion waits for the page itself.
function Test-ForkPort([string]$url) {
    $uri = [System.Uri]$url
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $client.BeginConnect($uri.Host, $uri.Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne(1000)) { return $false }
        $client.EndConnect($connect)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# Another companion.js already running under this account. The lock file is the
# enforcement; this is the courtesy.
function Get-RunningCompanion {
    try {
        return Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and $_.CommandLine -match 'companion\.js' }
    } catch {
        Write-Line "could not ask Windows which processes are running ($($_.Exception.Message)); leaving it to the lock file"
        return $null
    }
}

$settings = Get-CompanionConfig $Config

$running = Get-RunningCompanion
if ($running) {
    $pids = ($running | ForEach-Object { $_.ProcessId }) -join ', '
    Write-Line "a companion is already running (pid $pids); not starting a second one"
    exit 0
}

if (-not $NoFork -and $settings.startFork) {
    if (Test-ForkPort $settings.forkUrl) {
        Write-Line "the fork already answers $($settings.forkUrl)"
    } else {
        Write-Line "nothing answers $($settings.forkUrl); starting npm start in $($settings.forkPath)"
        if (-not (Test-Path -LiteralPath $settings.forkPath)) {
            Write-Line "there is no fork at $($settings.forkPath); the companion will say so again when it tries"
        } else {
            Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', 'npm', 'start' `
                -WorkingDirectory $settings.forkPath -WindowStyle Hidden | Out-Null
            $deadline = (Get-Date).AddSeconds([int]$settings.forkStartTimeoutSeconds)
            while ((Get-Date) -lt $deadline -and -not (Test-ForkPort $settings.forkUrl)) {
                Start-Sleep -Seconds 2
            }
            if (Test-ForkPort $settings.forkUrl) {
                Write-Line "the fork answers $($settings.forkUrl)"
            } else {
                Write-Line "the fork did not answer within $($settings.forkStartTimeoutSeconds)s; starting the watcher anyway - it retries on every /reload"
            }
        }
    }
}

$arguments = @('companion.js', '--watch')
if ($Config) { $arguments += @('--config', $Config) }
Write-Line "node $($arguments -join ' ')"
Push-Location $here
try {
    & node @arguments
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
