# p0-cleanup.ps1 — move top-level runnables into src, quarantine stubs into vendor/types

$repo = Get-Location
$src  = Join-Path $repo "src"
$destClient = Join-Path $src "Client"
$destServer = Join-Path $src "Server"
$vendorTypes = Join-Path $repo "vendor\types"

New-Item -ItemType Directory -Force $destClient, $destServer, $vendorTypes | Out-Null

function Move-Safe {
  param([string]$From, [string]$To)
  if ($From -ieq $To) { return }
  if (Test-Path $To) {
    $same = $false
    try {
      $h1 = (Get-FileHash -Algorithm SHA256 $From).Hash
      $h2 = (Get-FileHash -Algorithm SHA256 $To).Hash
      $same = ($h1 -eq $h2)
    } catch { $same = $false }

    if ($same) {
      Remove-Item $From -Force
      Write-Host "Duplicate removed: $From" -ForegroundColor DarkYellow
    } else {
      $alt = $To -replace '\.lua$', '.from_root.lua'
      if (Test-Path $alt) {
        $alt = $To -replace '\.lua$', ('.from_root.' + (Get-Date).ToString('yyyyMMddHHmmss') + '.lua')
      }
      Move-Item $From $alt -Force
      Write-Host "Conflict -> kept both: $From -> $alt" -ForegroundColor Magenta
    }
    return
  }
  Move-Item $From $To -Force
  Write-Host "Moved: $From -> $To" -ForegroundColor Green
}

# A) Move any TOP-LEVEL *.client.lua / *.server.lua from repo root to src
Get-ChildItem $repo -File -Filter *.client.lua |
  ForEach-Object { Move-Safe -From $_.FullName -To (Join-Path $destClient $_.Name) }

Get-ChildItem $repo -File -Filter *.server.lua |
  ForEach-Object { Move-Safe -From $_.FullName -To (Join-Path $destServer $_.Name) }

# B) Quarantine TOP-LEVEL stub/spec files into vendor/types
#    Heuristics:
#    - *_spec.lua at repo root
#    - Any other .lua at repo root (not src/scripts/vendor/Packages) is likely clutter from API stubs
$skip = @('src','scripts','vendor','Packages','.git','.vscode')
$topLevelLua = Get-ChildItem $repo -File -Filter *.lua | Where-Object {
  $name = $_.Name
  -not ($skip -contains $name)
}

foreach ($f in $topLevelLua) {
  $dest = Join-Path $vendorTypes $f.Name
  Move-Safe -From $f.FullName -To $dest
}

Write-Host "P0 cleanup complete." -ForegroundColor Green
