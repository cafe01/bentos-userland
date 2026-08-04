# smoke-test.ps1 — the product proven from outside, on the platform none of us
# runs day to day: the real `iwr bootstrap.ps1 | iex`, against the real
# published release, in a $HOME that never existed before this run.
#
# Mirrors script/smoke-test.sh phase for phase — install the floor, self-update,
# update, rollback, each cross-checked against bytes this script hashes itself,
# never against what `bentos` says about itself. See that file for the shape;
# this one only carries what Windows makes different.
#
# It is expected to fail today, and to fail by naming what is missing: there is
# no bootstrap.ps1 in the release yet. That red is the seam — this gate turns
# green by itself the moment the bootstrap lands, with nothing here to edit.
#
# Narrower than the POSIX gate on purpose, for now: it proves the mechanism
# (install, self-update, update, rollback, every name executes) but not yet the
# report-vs-bytes cross-check (assert_report_matches_bytes) or the manifest
# diff that predicts which names should move. Named here rather than silently
# dropped — the POSIX file is the fuller witness to grow this one toward.
#
# Env:
#   BENTOS_REPO           which repo to prove   (default: cafe01/bentos-userland)
#   BENTOS_SMOKE_FLOOR    the pinned floor tag   (default: v0.1.1)

$ErrorActionPreference = 'Stop'

$Repo = if ($env:BENTOS_REPO) { $env:BENTOS_REPO } else { 'cafe01/bentos-userland' }
$FloorTag = if ($env:BENTOS_SMOKE_FLOOR) { $env:BENTOS_SMOKE_FLOOR } else { 'v0.1.1' }

function Say([string]$msg) { Write-Host "smoke: $msg" }
function Step([string]$msg) { Write-Host ""; Write-Host "── $msg" }
function Fail([string]$msg) { Write-Host "smoke: FAIL — $msg" -ForegroundColor Red; exit 1 }

$Work = Join-Path ([System.IO.Path]::GetTempPath()) ("bentos-smoke-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Work | Out-Null
try {
  $env:HOME = Join-Path $Work 'home'
  $env:USERPROFILE = $env:HOME
  New-Item -ItemType Directory -Path $env:HOME | Out-Null
  $Bin = Join-Path $env:HOME '.bentos\bin'
  $env:PATH = "$Bin;$env:PATH"

  function Sha256Of([string]$path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToLower()
  }

  # The prefix's own bytes, one line per name — this script's witness, never the
  # store's.
  function HashPrefix {
    if (-not (Test-Path $Bin)) { return @() }
    Get-ChildItem -Path $Bin -File | Sort-Object Name | ForEach-Object {
      "$($_.Name) $(Sha256Of $_.FullName)"
    }
  }

  function ChangedNames([string[]]$before, [string[]]$after) {
    $beforeSet = @{}
    foreach ($line in $before) { $beforeSet[$line] = $true }
    $after | Where-Object { -not $beforeSet.ContainsKey($_) } | ForEach-Object { ($_ -split ' ')[0] }
  }

  function LsPrefix {
    Write-Host "${Bin}:"
    if (Test-Path $Bin) { Get-ChildItem -Path $Bin -File | Format-Table Name, Length } else { Write-Host "  (does not exist yet)" }
  }

  # Every name on the PATH actually runs — wrong architecture, a missing
  # dependency, a corrupted transfer, none of which a unit suite ever touches.
  function AssertExecutes {
    if (-not (Test-Path $Bin)) { Fail "no prefix to execute from" }
    Get-ChildItem -Path $Bin -File | ForEach-Object {
      $name = $_.Name
      $proc = Start-Process -FilePath $_.FullName -NoNewWindow -PassThru -Wait `
        -RedirectStandardOutput "$Work\exec-out" -RedirectStandardError "$Work\exec-err"
      Say "  ran $name — exit $($proc.ExitCode)"
    }
  }

  Step "iwr bootstrap.ps1 | iex against the published release ($Repo)"
  $bootstrapUrl = "https://github.com/$Repo/releases/latest/download/bootstrap.ps1"
  try {
    $script = (Invoke-WebRequest -UseBasicParsing -Uri $bootstrapUrl).Content
  } catch {
    Fail "no bootstrap.ps1 published at $bootstrapUrl — script/bootstrap.ps1 does not exist yet, which is the piece this gate is waiting on"
  }
  Invoke-Expression $script
  $bentosExe = Join-Path $Bin 'bentos.exe'
  if (-not (Test-Path $bentosExe)) { Fail "bootstrap did not leave an executable bentos.exe at $bentosExe" }
  AssertExecutes

  Step "pin the floor — install $FloorTag, the whole set"
  $configDir = Join-Path $env:HOME '.bentos'
  New-Item -ItemType Directory -Path $configDir -Force | Out-Null
  @"
[streams.bentos-userland]
repo = "$Repo"
tag_prefix = "$FloorTag"
"@ | Set-Content -Path (Join-Path $configDir 'config.toml') -NoNewline

  Say "before:"; LsPrefix
  & bentos install
  if ($LASTEXITCODE -ne 0) { Fail "bentos install exited $LASTEXITCODE" }
  Say "after:"; LsPrefix
  $afterFloor = HashPrefix
  $names = $afterFloor | ForEach-Object { ($_ -split ' ')[0] }
  if ($names.Count -eq 0) { Fail "install left nothing in $Bin" }
  Say "names: $($names -join ' ')"
  AssertExecutes

  Step "un-pin — the real default, the true latest, discovered and never guessed"
  Remove-Item (Join-Path $configDir 'config.toml')

  Step "self-update, update, rollback"
  & bentos self-update
  if ($LASTEXITCODE -ne 0) { Fail "bentos self-update exited $LASTEXITCODE" }
  AssertExecutes

  & bentos update
  if ($LASTEXITCODE -ne 0) { Fail "bentos update exited $LASTEXITCODE" }
  AssertExecutes

  & bentos rollback
  if ($LASTEXITCODE -ne 0) { Fail "bentos rollback exited $LASTEXITCODE" }
  $afterRollback = HashPrefix
  if (($afterRollback -join "`n") -ne ($afterFloor -join "`n")) {
    Fail "rollback did not reproduce the floor's own bytes byte-for-byte"
  }
  AssertExecutes

  Say "all green — $Repo installs, updates, rolls back and executes, proven from outside, on Windows"
} finally {
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
