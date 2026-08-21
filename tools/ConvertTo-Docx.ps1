# ConvertTo-Docx.ps1
# Turn one of the docs/*.md files into a Word .docx for sending to a customer.
#
#   .\tools\ConvertTo-Docx.ps1 -Markdown docs\DEPLOYMENT.md `
#       -Out docs\Quality-App-Mobile-Deployment-and-Licensing.docx `
#       -Title "Deploying Quality App Mobile to Another Environment"
#
# WHY THIS EXISTS
# This machine has no Word COM, no pandoc and no LibreOffice. A .docx is just a zip of
# OOXML parts, so tools\md2docx.js emits the parts and this script packages them.
#
# THE TRAP THIS SCRIPT EXISTS TO AVOID
# [System.IO.Compression.ZipFile]::CreateFromDirectory writes entry names with BACKSLASHES
# on .NET Framework / Windows. The OOXML and ZIP specs both require forward slashes, and
# Word rejects such a file with "there are problems with the contents" -- while every other
# check (valid zip, well-formed XML, correct namespaces) still passes, so it looks fine right
# up until someone tries to open it. Entries are therefore added explicitly, in order, with
# [Content_Types].xml first.
#
# Also note Test-Path needs -LiteralPath here: the square brackets in [Content_Types].xml
# are treated as a wildcard character class otherwise, and the part is reported missing.
#
# ASCII-only per project standard.

param(
    [Parameter(Mandatory=$true)][string]$Markdown,
    [Parameter(Mandatory=$true)][string]$Out,
    [string]$Title
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "node is required and was not found on PATH." }

$md = if ([System.IO.Path]::IsPathRooted($Markdown)) { $Markdown } else { Join-Path $repo $Markdown }
$outFile = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $repo $Out }
if (-not (Test-Path -LiteralPath $md)) { throw "markdown not found: $md" }
if (-not $Title) { $Title = [System.IO.Path]::GetFileNameWithoutExtension($md) }

$parts = Join-Path ([System.IO.Path]::GetTempPath()) ("docxparts_" + [guid]::NewGuid().ToString('N'))

Write-Output "=== 1. emit OOXML parts ==="
& node (Join-Path $here 'md2docx.js') $md $parts $Title
if ($LASTEXITCODE -ne 0) { throw "md2docx.js failed" }

Write-Output ""
Write-Output "=== 2. package as .docx ==="
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }

# [Content_Types].xml must be first. Forward slashes are mandatory -- see header.
$order = @('[Content_Types].xml', '_rels/.rels', 'docProps/core.xml', 'word/document.xml')

$fs  = [System.IO.File]::Open($outFile, [System.IO.FileMode]::CreateNew)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $order) {
        $src = Join-Path $parts ($name -replace '/', '\')
        if (-not (Test-Path -LiteralPath $src)) { throw "missing part: $src" }
        $entry = $zip.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
        $es = $entry.Open()
        $bytes = [System.IO.File]::ReadAllBytes($src)
        $es.Write($bytes, 0, $bytes.Length)
        $es.Dispose()
        Write-Output ("  + {0,-28} {1,8:N0} bytes" -f $name, $bytes.Length)
    }
} finally { $zip.Dispose(); $fs.Dispose() }

Remove-Item -LiteralPath $parts -Recurse -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "=== 3. verify ==="
$zr = [System.IO.Compression.ZipFile]::OpenRead($outFile)
$bad = @($zr.Entries | Where-Object { $_.FullName -match '\\' })
$doc = $zr.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
if (-not $doc) { $zr.Dispose(); throw "word/document.xml missing from package" }
$sr = New-Object System.IO.StreamReader($doc.Open())
$xmlText = $sr.ReadToEnd(); $sr.Close(); $zr.Dispose()
if ($bad.Count -gt 0) { throw "entry names contain backslashes -- Word will refuse this file" }
$xd = New-Object System.Xml.XmlDocument
$xd.LoadXml($xmlText)   # throws if malformed
$ns = New-Object System.Xml.XmlNamespaceManager($xd.NameTable)
$ns.AddNamespace('w','http://schemas.openxmlformats.org/wordprocessingml/2006/main')

Write-Output ("  entry names : forward slashes OK")
Write-Output ("  document.xml: well-formed")
Write-Output ("  paragraphs  : {0}" -f $xd.SelectNodes('//w:p',$ns).Count)
Write-Output ("  tables      : {0}" -f $xd.SelectNodes('//w:tbl',$ns).Count)
Write-Output ""
Write-Output ("created: {0}  ({1:N0} bytes)" -f $outFile, (Get-Item -LiteralPath $outFile).Length)
Write-Output ""
Write-Output "NOTE: these checks prove the package is structurally valid. They do NOT prove"
Write-Output "Word renders it as intended -- open it once before sending it to a customer."
