# Publish-QmCanvasApp.ps1
# Push a generated .msapp back into the environment.
#
# pac canvas has no upload verb, but the app is now a solution component (type 300) in the
# target system -- which is what the earlier attempt lacked. So: export the real solution,
# swap the .msapp payload, bump the version, re-import.
#
# Safe by construction: the package is the EXPORTED solution, so it already contains every
# component. Never hand-build a solution zip against a live solution name -- a minimal
# customizations.xml plus --force-overwrite can strip components.
#
# ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$NewMsapp     = 'C:\Quality Agents\phase2\canvas\gen2.msapp',
    [string]$Work         = 'C:\Quality Agents\phase2\canvas\publish'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'phase1\scripts\dvlib.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $NewMsapp)) { throw "Generated msapp not found: $NewMsapp" }
if (Test-Path $Work) { Get-ChildItem $Work -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path "$Work\extract" | Out-Null

$exportZip = "$Work\exported.zip"

Write-Output "=== 1. export the live solution ==="
& pac solution export --name $SolutionName --path $exportZip --overwrite *>&1 | Select-Object -Last 2
if (-not (Test-Path $exportZip)) { throw "Export produced no zip." }
Write-Output "  exported $((Get-Item $exportZip).Length) bytes"

Write-Output ""
Write-Output "=== 2. extract ==="
[System.IO.Compression.ZipFile]::ExtractToDirectory($exportZip, "$Work\extract")
$canvasFiles = Get-ChildItem "$Work\extract\CanvasApps" -File -ErrorAction SilentlyContinue
if (-not $canvasFiles) { throw "No CanvasApps folder in the exported solution -- is the app a component?" }
$canvasFiles | ForEach-Object { Write-Output ("  {0,-56} {1,8} bytes" -f $_.Name, $_.Length) }

$target = $canvasFiles | Where-Object { $_.Extension -eq '.msapp' } | Select-Object -First 1
if (-not $target) { throw "No .msapp found in CanvasApps." }

Write-Output ""
Write-Output "=== 3. swap the payload ==="
Write-Output ("  {0}" -f $target.Name)
Write-Output ("  {0} bytes -> {1} bytes" -f $target.Length, (Get-Item $NewMsapp).Length)
Copy-Item $NewMsapp $target.FullName -Force

Write-Output ""
Write-Output "=== 4. bump solution version ==="
$solXmlPath = "$Work\extract\solution.xml"
[xml]$sx = Get-Content $solXmlPath
$cur = [version]$sx.ImportExportXml.SolutionManifest.Version
$new = "{0}.{1}.{2}.{3}" -f $cur.Major, $cur.Minor, ($cur.Build + 1), 0
$sx.ImportExportXml.SolutionManifest.Version = $new
$sx.Save($solXmlPath)
Write-Output "  $cur -> $new"

Write-Output ""
Write-Output "=== 5. repackage ==="
# GOTCHA: [ZipFile]::CreateFromDirectory on .NET Framework writes BACKSLASH path separators
# into the archive. The solution importer matches entries by forward-slash path and fails
# with "Xaml file is missing from import zip file" for anything in a subfolder. Build the
# archive entry by entry with explicit forward slashes.
$importZip = "$Work\import.zip"
if (Test-Path $importZip) { Remove-Item $importZip -Force }

$root = (Resolve-Path "$Work\extract").Path.TrimEnd('\')
$fs   = [System.IO.File]::Open($importZip, [System.IO.FileMode]::Create)
$zip  = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in (Get-ChildItem $root -Recurse -File)) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $es = $entry.Open()
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $es.Write($bytes, 0, $bytes.Length)
        $es.Close()
    }
} finally {
    $zip.Dispose(); $fs.Dispose()
}
Write-Output "  $((Get-Item $importZip).Length) bytes (forward-slash entries)"

Write-Output ""
Write-Output "=== 6. import ==="
& pac solution import --path $importZip --force-overwrite --publish-changes --max-async-wait-time 20 *>&1 | Select-Object -First 14
