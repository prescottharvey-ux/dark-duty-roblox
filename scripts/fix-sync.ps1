# fix-sync.ps1 — normalize Script Sync filenames for Rojo
# - Converts *.client.lua.local.luau → *.client.lua (etc.)
# - Converts stray *.luau → *.lua in Shared/Server
# - If a destination already exists, keeps both:
#     - deletes the source if contents are identical
#     - otherwise renames source to *.from_sync.lua

$root = Join-Path (Get-Location) "src"

function Rename-Safe {
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
      $alt = $To -replace '\.lua$', '.from_sync.lua'
      if (Test-Path $alt) {
        $alt = $To -replace '\.lua$', ('.from_sync.' + (Get-Date).ToString('yyyyMMddHHmmss') + '.lua')
      }
      Rename-Item $From $alt -Force
      Write-Host "Conflict → kept both: $From -> $alt" -ForegroundColor Magenta
    }
    return
  }

  Rename-Item $From $To -Force
  Write-Host "Renamed: $From -> $To" -ForegroundColor Green
}

# 1) *.client.lua.local.luau → *.client.lua
Get-ChildItem "$root" -Recurse -File -Filter *.client.lua.local.luau |
  ForEach-Object {
    $dest = $_.FullName -replace '\.client\.lua\.local\.luau$', '.client.lua'
    Rename-Safe -From $_.FullName -To $dest
  }

# 2) *.server.lua.local.luau → *.server.lua
Get-ChildItem "$root" -Recurse -File -Filter *.server.lua.local.luau |
  ForEach-Object {
    $dest = $_.FullName -replace '\.server\.lua\.local\.luau$', '.server.lua'
    Rename-Safe -From $_.FullName -To $dest
  }

# 3) Any leftover *.local.luau under Client → *.client.lua
Get-ChildItem "$root\Client" -Recurse -File -Filter *.local.luau |
  ForEach-Object {
    $dest = $_.FullName -replace '\.local\.luau$', '.client.lua'
    Rename-Safe -From $_.FullName -To $dest
  }

# 4) Normalize *.client.luau / *.server.luau → *.client.lua / *.server.lua
Get-ChildItem "$root" -Recurse -File -Filter *.client.luau |
  ForEach-Object { Rename-Safe -From $_.FullName -To ($_.FullName -replace '\.client\.luau$', '.client.lua') }

Get-ChildItem "$root" -Recurse -File -Filter *.server.luau |
  ForEach-Object { Rename-Safe -From $_.FullName -To ($_.FullName -replace '\.server\.luau$', '.server.lua') }

# 5) Shared/Server modules: *.luau → *.lua (avoid client/server runnables)
Get-ChildItem "$root\Shared" -Recurse -File -Filter *.luau |
  ForEach-Object { Rename-Safe -From $_.FullName -To ($_.FullName -replace '\.luau$', '.lua') }

Get-ChildItem "$root\Server" -Recurse -File -Filter *.luau |
  Where-Object { $_.Name -notmatch '\.(client|server)\.luau$' } |
  ForEach-Object { Rename-Safe -From $_.FullName -To ($_.FullName -replace '\.luau$', '.lua') }

Write-Host "Filename normalization complete." -ForegroundColor Green

