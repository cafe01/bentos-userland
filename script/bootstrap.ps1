# bootstrap.ps1 — put `bentos` on a Windows machine that has nothing.
#
#   iwr <url>/bootstrap.ps1 -UseBasicParsing | iex
#
# Mirrors script/bootstrap.sh phase for phase — same manifest, same resolution
# by tag prefix, same verify-then-move — with only what Windows makes
# different: the artifact lands as bentos.exe (VersionStore's own naming rule
# under Windows semantics — see store.dart's _prefixName — applies here too,
# since this script writes the very first version that rule will ever have to
# agree with).
#
# This fetches exactly one thing and exits. Everything after — installing the
# coreutils, updating them, updating itself — is the binary's own job.
#
# Where it lands is not a choice: $BENTOS_HOME\bin is the directory the
# installer owns and substitutes into, and staging happens inside the same
# home so every move stays on one volume.
#
# Env:
#   BENTOS_HOME       the installer's own root      (default: $HOME\.bentos)
#   GH_TOKEN          token, if the repo is private (also honours GITHUB_TOKEN)
#   BENTOS_REPO       stream to install from        (default: cafe01/bentos-userland)
#   BENTOS_TAG_PREFIX release series in that repo   (default: v)

$ErrorActionPreference = 'Stop'

$ExecName = 'bentos'
$Repo = if ($env:BENTOS_REPO) { $env:BENTOS_REPO } else { 'cafe01/bentos-userland' }
$TagPrefix = if ($env:BENTOS_TAG_PREFIX) { $env:BENTOS_TAG_PREFIX } else { 'v' }
$BentosHome = if ($env:BENTOS_HOME) { $env:BENTOS_HOME } else { Join-Path $env:USERPROFILE '.bentos' }
$Prefix = Join-Path $BentosHome 'bin'
$Staging = Join-Path $BentosHome 'staging'
$Token = if ($env:GH_TOKEN) { $env:GH_TOKEN } elseif ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } else { '' }
$Api = "https://api.github.com/repos/$Repo"

function Die([string]$msg) {
  Write-Host "bentos: $msg" -ForegroundColor Red
  exit 1
}

# curl-equivalent against the API, carrying the token only when there is one —
# the same code path both sides of the public/private seam.
function ApiGet([string]$url) {
  $headers = @{ 'User-Agent' = 'bentos-bootstrap' }
  if ($Token) { $headers['Authorization'] = "Bearer $Token" }
  Invoke-RestMethod -Uri $url -Headers $headers
}

function ApiDownload([string]$url, [string]$dest, [bool]$asOctetStream) {
  $headers = @{ 'User-Agent' = 'bentos-bootstrap' }
  if ($Token) { $headers['Authorization'] = "Bearer $Token" }
  if ($asOctetStream) { $headers['Accept'] = 'application/octet-stream' }
  Invoke-WebRequest -Uri $url -Headers $headers -OutFile $dest -UseBasicParsing
}

# ── platform ─────────────────────────────────────────────────────────────
# Only windows-x64 runs this script at all, but the arch is still read rather
# than assumed — arm64 Windows exists and must be told apart, not silently
# handed an x64 binary.
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'x64' }
  'ARM64' { 'arm64' }
  default { $env:PROCESSOR_ARCHITECTURE }
}
if ($arch -ne 'x64' -and $arch -ne 'arm64') {
  Die "unsupported architecture: $env:PROCESSOR_ARCHITECTURE"
}
$Platform = "windows-$arch"

# ── the release ──────────────────────────────────────────────────────────
# Resolved by tag prefix and never by "latest": one repo carries several
# products, and "latest" is whichever of them published most recently.
try {
  $releases = ApiGet "$Api/releases?per_page=100"
} catch {
  Die "cannot read releases of $Repo (private repo? set GH_TOKEN) — $($_.Exception.Message)"
}
$tag = $releases |
  Where-Object { $_.tag_name -like "$TagPrefix*" } |
  Sort-Object { [version]($_.tag_name -replace '^[^\d]*', '') } -Descending |
  Select-Object -First 1 -ExpandProperty tag_name
if (-not $tag) { Die "no release tagged $TagPrefix* in $Repo" }

try {
  $release = ApiGet "$Api/releases/tags/$tag"
} catch {
  Die "cannot read release $tag — $($_.Exception.Message)"
}

function FindAsset([string]$name) {
  $release.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
}

function FetchAsset($asset, [string]$dest) {
  if ($Token) {
    ApiDownload "$Api/releases/assets/$($asset.id)" $dest $true
  } else {
    ApiDownload $asset.browser_download_url $dest $false
  }
}

# Staged inside the installer's own home and never in the machine's temp: the
# last act of this script is a move into $Prefix, and %TEMP% is commonly a
# different volume, where that move would refuse rather than degrade.
New-Item -ItemType Directory -Path $Staging -Force | Out-Null
$tmp = Join-Path $Staging ([System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  # ── the manifest decides ────────────────────────────────────────────────
  # What is downloaded and what it must hash to are read from the release's
  # own manifest, never assembled from a naming convention here.
  $manifestAsset = FindAsset 'bentos-release.json'
  if (-not $manifestAsset) { Die "release $tag carries no bentos-release.json" }
  $manifestPath = Join-Path $tmp 'manifest.json'
  FetchAsset $manifestAsset $manifestPath
  $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

  $entry = $manifest.artifacts | Where-Object {
    $_.name -eq $ExecName -and $_.platform -eq $Platform
  } | Select-Object -First 1
  if (-not $entry) {
    Die "release $tag has no $ExecName built for $Platform — nothing was installed"
  }
  if (-not $entry.asset -or -not $entry.sha256) {
    Die "malformed artifact entry for $ExecName in $tag"
  }

  Write-Host "bentos: $tag · $Platform · $($entry.asset)"
  $assetInfo = FindAsset $entry.asset
  if (-not $assetInfo) { Die "release $tag declares $($entry.asset) and does not carry it" }
  $downloaded = Join-Path $tmp $ExecName
  FetchAsset $assetInfo $downloaded

  # ── verify, then substitute ──────────────────────────────────────────────
  # The hash is checked before anything is placed, and the move into $Prefix
  # is the last act, so an interrupted run never leaves a half-written binary
  # where a working one was.
  $got = (Get-FileHash -Path $downloaded -Algorithm SHA256).Hash.ToLower()
  $want = $entry.sha256.ToLower()
  if ($got -ne $want) { Die "sha256 mismatch for $($entry.asset) — expected $want, got $got" }

  New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
  # The prefix name carries .exe — the same rule VersionStore applies under
  # windowsSemantics, so the first version this script places already agrees
  # with every version `bentos install`/`self-update` will place after it.
  $destination = Join-Path $Prefix "$ExecName.exe"
  if (Test-Path $destination) { Remove-Item $destination -Force }
  Move-Item -Path $downloaded -Destination $destination -Force

  Write-Host "bentos: installed $destination"

  # setx is deliberately not used: it truncates at 1024 characters and writes
  # the *expanded* value, silently destroying a long user PATH. Written to the
  # registry directly instead, REG_EXPAND_SZ preserved, existing entries kept
  # verbatim — this is HKCU\Environment, the user's own PATH, never the
  # machine-wide one, so it needs no elevation.
  $envKey = 'HKCU:\Environment'
  $raw = (Get-Item -Path $envKey).GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $entries = @()
  if ($raw) { $entries = $raw -split ';' | Where-Object { $_ -ne '' } }
  $alreadyOnPath = $entries -contains $Prefix
  if (-not $alreadyOnPath) {
    $newValue = if ($raw) { "$raw;$Prefix" } else { $Prefix }
    Set-ItemProperty -Path $envKey -Name 'Path' -Value $newValue -Type ExpandString
    Write-Host "bentos: added $Prefix to your user PATH"

    # Broadcast the change so processes started after this one pick it up
    # without a logoff — the running shell that launched this script does not
    # inherit its own write, and is told so explicitly.
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero
    Add-Type -Namespace Bentos -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
    [Bentos.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result) | Out-Null

    Write-Host "bentos: this terminal will not see it — open a new one, or run:"
    Write-Host "        `$env:PATH = `"$Prefix;`$env:PATH`""
  } else {
    # Idempotent: a second bootstrap on a machine that already has the entry
    # writes nothing and duplicates nothing.
    Write-Host "bentos: $Prefix already on your user PATH"
  }
  Write-Host "bentos: next — bentos install"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
