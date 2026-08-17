# Publish-CanvasApp.ps1
# Push edited screen YAML back to the environment.
#
#   1. pack canvas-src/*.pa.yaml into a .msapp
#   2. export the live solution
#   3. swap the .msapp payload, bump the version
#   4. re-zip with FORWARD-SLASH entries and import
#
# Always swaps the payload inside a freshly EXPORTED solution. Never hand-build a solution
# zip against a live solution name -- a minimal customizations.xml plus --force-overwrite
# can strip components.
#
# After importing, OPEN THE APP IN STUDIO. pac canvas validate is retired and pack does not
# check Power Fx semantics, so formula errors surface only there.
#
# Run from the repo root. ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$Environment
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
$cvs  = Join-Path $repo "solution\$SolutionName\canvas-src"
$work = Join-Path $repo 'canvas-work'
if (Test-Path $work) { Get-ChildItem $work -Recurse | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path "$work\extract" | Out-Null

$envArg = @()
if ($Environment) { $envArg = @('--environment', $Environment) }

Write-Output "=== 0. guard: ASCII-only check on screen source ==="
$bad = 0
foreach ($f in Get-ChildItem (Join-Path $cvs 'Src') -Filter '*.pa.yaml') {
    $t = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
    $m = [regex]::Matches($t, '[^\x00-\x7F]')
    if ($m.Count -gt 0) { Write-Output "  $($f.Name): $($m.Count) non-ASCII characters"; $bad++ }
}
if ($bad -gt 0) { throw "Non-ASCII characters in screen source. They corrupt through PowerShell's cp1252 round-trip -- replace them before publishing." }
Write-Output "  clean"

Write-Output ""
Write-Output "=== 1. pack canvas source ==="
$newMsapp = "$work\generated.msapp"
& pac canvas pack --sources $cvs --msapp $newMsapp --layout SourceCode --overwrite
if (-not (Test-Path $newMsapp)) { throw "Pack produced no .msapp" }
Write-Output "  $((Get-Item $newMsapp).Length) bytes"

Write-Output ""
Write-Output "=== 2. export the live solution ==="
$exportZip = "$work\exported.zip"
& pac solution export --name $SolutionName --path $exportZip --overwrite @envArg
[System.IO.Compression.ZipFile]::ExtractToDirectory($exportZip, "$work\extract")

Write-Output ""
Write-Output "=== 3. swap payload and bump version ==="
$target = Get-ChildItem "$work\extract\CanvasApps" -Filter '*.msapp' | Select-Object -First 1
if (-not $target) { throw "No canvas app in the exported solution." }
Write-Output ("  {0}: {1} -> {2} bytes" -f $target.Name, $target.Length, (Get-Item $newMsapp).Length)
Copy-Item $newMsapp $target.FullName -Force

$solXml = "$work\extract\solution.xml"
[xml]$sx = Get-Content $solXml
$cur = [version]$sx.ImportExportXml.SolutionManifest.Version
$sx.ImportExportXml.SolutionManifest.Version = "{0}.{1}.{2}.{3}" -f $cur.Major, $cur.Minor, ($cur.Build + 1), 0
$sx.Save($solXml)
Write-Output ("  version {0} -> {1}" -f $cur, $sx.ImportExportXml.SolutionManifest.Version)

Write-Output ""
Write-Output "=== 4. repackage with forward-slash entries ==="
# [ZipFile]::CreateFromDirectory on .NET Framework writes BACKSLASH separators; the solution
# importer matches on forward slashes and fails with "Xaml file is missing from import zip file".
$importZip = "$work\import.zip"
$root = (Resolve-Path "$work\extract").Path.TrimEnd('\')
$fs  = [System.IO.File]::Open($importZip, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($f in (Get-ChildItem $root -Recurse -File)) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        $e = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
        $s = $e.Open()
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $s.Write($bytes, 0, $bytes.Length)
        $s.Close()
    }
} finally { $zip.Dispose(); $fs.Dispose() }
Write-Output "  $((Get-Item $importZip).Length) bytes"

Write-Output ""
Write-Output "=== 5. import ==="
& pac solution import --path $importZip --force-overwrite --publish-changes --max-async-wait-time 20 @envArg

Write-Output ""
Write-Output "=== 6. re-arm the flows ==="
# MANDATORY after any solution import. The import leaves flows reading statecode 1/2 while
# their Dataverse webhook registration is gone, so they silently stop firing and outbox rows
# sit at Queued with no error. See Repair-FlowTriggers.ps1 for the full account.
& (Join-Path $here 'Repair-FlowTriggers.ps1') -SolutionName $SolutionName

Write-Output ""
Write-Output "Imported and re-armed."
Write-Output ""
Write-Output "STILL TO DO BY HAND:"
Write-Output "  1. Open the app in Power Apps Studio to validate the Power Fx. pack does not"
Write-Output "     check formula semantics and 'pac canvas validate' is retired."
Write-Output "  2. Prove a round trip -- submit a result and watch the queue reach Confirmed."
Write-Output "     A flow reading 1/2 is not proof that its trigger fires."
Write-Output "  3. Run tools\Export-Solution.ps1 and commit the refreshed source."
