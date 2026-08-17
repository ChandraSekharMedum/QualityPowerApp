# Export-Solution.ps1
# Pull the live environment into source control.
#
#   1. export QualityManagementApp (unmanaged and managed)
#   2. unpack to solution/QualityManagementApp/src  (SolutionPackager, packagetype Both)
#   3. unpack the canvas app to solution/QualityManagementApp/canvas-src as .pa.yaml
#
# Step 3 exists because pac solution unpack stores a canvas app as a binary .msapp, which
# gives no useful diff. The YAML is generated for review; the .msapp stays authoritative.
#
# Run from the repo root. ASCII-only per project standard.

param(
    [string]$SolutionName = 'QualityManagementApp',
    [string]$Environment
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$src  = Join-Path $repo "solution\$SolutionName\src"
$cvs  = Join-Path $repo "solution\$SolutionName\canvas-src"
$out  = Join-Path $repo 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$envArg = @()
if ($Environment) { $envArg = @('--environment', $Environment) }

Write-Output "=== 1. export ==="
& pac solution export --name $SolutionName --path "$out\$SolutionName.zip" --managed false --overwrite @envArg
& pac solution export --name $SolutionName --path "$out\${SolutionName}_managed.zip" --managed true --overwrite @envArg

Write-Output ""
Write-Output "=== 2. unpack solution ==="
& pac solution unpack --zipfile "$out\$SolutionName.zip" --folder $src --packagetype Both --allowDelete --allowWrite

Write-Output ""
Write-Output "=== 3. unpack canvas app to reviewable YAML ==="
$msapp = Get-ChildItem (Join-Path $src 'CanvasApps') -Filter '*.msapp' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($msapp) {
    & pac canvas unpack --msapp $msapp.FullName --sources $cvs --layout SourceCode --overwrite
    Write-Output "  $($msapp.Name) -> canvas-src/"
} else {
    Write-Output "  no canvas app in the solution"
}

Write-Output ""
Write-Output "Done. Review with 'git status' and commit."
