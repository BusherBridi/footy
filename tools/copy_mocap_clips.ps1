# Copies the chosen CMU mocap clips from the downloaded pack into the game.
#
# Expected layout (the default):
#   <parent>\Animations_V1_01\packed\Animations\...   (the unzipped pack)
#   <parent>\footy\                                    (this repo)
#
# Run from Windows Terminal (PowerShell), inside the footy folder:
#   powershell -ExecutionPolicy Bypass -File tools\copy_mocap_clips.ps1
# Add -Push to also commit and push the clips:
#   powershell -ExecutionPolicy Bypass -File tools\copy_mocap_clips.ps1 -Push
# If the pack is somewhere else:
#   powershell -ExecutionPolicy Bypass -File tools\copy_mocap_clips.ps1 -Source "D:\stuff\Animations_V1_01"

param(
    [string]$Source = "",
    [switch]$Push
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if ($Source -eq "") {
    $Source = Join-Path (Split-Path -Parent $repo) "Animations_V1_01"
}
$dest = Join-Path $repo "godot\assets\mocap_clips"

# The clips picked from the index (see the chat / CREDITS): id -> what it's for.
$clips = [ordered]@{
    "33_01"  = "football throw + catch";      "34_01"  = "football throw + catch";
    "33_02"  = "football throw, catch, jump"; "124_12" = "underhand toss (lateral)";
    "78_15"  = "juke: go right";              "78_16"  = "juke: go left";
    "78_20"  = "feint left, move right";      "78_21"  = "feint right, move left";
    "78_13"  = "spin left";                   "78_17"  = "spin right";
    "78_29"  = "defensive side to side";      "78_24"  = "defensive straight";
    "76_11"  = "quick steps backwards";       "127_23" = "run, dive over, roll";
    "128_10" = "run, dive over, roll";        "127_25" = "run, jump over";
    "127_27" = "run, jump over";              "82_06"  = "push heavy object";
    "81_06"  = "push heavy box";              "140_01" = "get up face down";
    "140_08" = "get up from back";            "124_11" = "two-foot jump";
    "118_20" = "jump";                        "127_05" = "run to quick stop"
}

if (-not (Test-Path $Source)) {
    Write-Host "Can't find the pack at: $Source" -ForegroundColor Red
    Write-Host "Pass its location with -Source `"C:\path\to\Animations_V1_01`""
    exit 1
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "Looking for clips under $Source ..."
$files = Get-ChildItem -Path $Source -Recurse -File -Include *.fbx, *.glb, *.gltf
Write-Host ("  {0} animation files found in the pack" -f $files.Count)

$copied = 0
$missing = @()
$totalBytes = 0
foreach ($id in $clips.Keys) {
    # Match the id as a whole number pair: "33_01" but not "133_01" or "33_011".
    $pattern = "(^|[^0-9])" + [regex]::Escape($id) + "([^0-9]|$)"
    $found = @($files | Where-Object { $_.BaseName -match $pattern })
    if ($found.Count -eq 0) {
        $missing += $id
        Write-Host ("  MISSING  {0,-7} {1}" -f $id, $clips[$id]) -ForegroundColor Yellow
        continue
    }
    # Prefer .fbx if there are several formats of the same clip.
    $pick = ($found | Sort-Object { if ($_.Extension -eq ".fbx") { 0 } else { 1 } }, Length)[0]
    $target = Join-Path $dest ($id + $pick.Extension.ToLower())
    Copy-Item -Path $pick.FullName -Destination $target -Force
    $copied++
    $totalBytes += $pick.Length
    $note = ""
    if ($found.Count -gt 1) { $note = "  ($($found.Count) matches, took $($pick.Name))" }
    Write-Host ("  ok       {0,-7} {1}{2}" -f $id, $clips[$id], $note) -ForegroundColor Green
}

Write-Host ""
Write-Host ("Copied {0} of {1} clips ({2:N1} MB) to {3}" -f $copied, $clips.Count, ($totalBytes / 1MB), $dest)
if ($missing.Count -gt 0) {
    Write-Host ("Not found: {0}. Send me a few file names from the pack and I'll fix the matching." -f ($missing -join ", ")) -ForegroundColor Yellow
}
if ($totalBytes -gt 100MB) {
    Write-Host "That's big for git. Tell me before pushing and we'll trim it down." -ForegroundColor Yellow
}

if ($Push -and $copied -gt 0) {
    Push-Location $repo
    try {
        git add "godot/assets/mocap_clips"
        git commit -m "CMU mocap clips for the animation comparison"
        git push
    } finally {
        Pop-Location
    }
} elseif ($copied -gt 0) {
    Write-Host ""
    Write-Host "To send them up:"
    Write-Host "  git add godot/assets/mocap_clips"
    Write-Host "  git commit -m `"CMU mocap clips`""
    Write-Host "  git push"
}
