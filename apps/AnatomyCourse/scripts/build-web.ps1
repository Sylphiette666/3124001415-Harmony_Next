param([string]$NodePath = 'node', [switch]$Install, [string]$NpmCliPath = '')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskNode = (Get-Command $NodePath -ErrorAction Stop).Source
$taskMajor = [int]((& $taskNode -p 'process.versions.node.split(".")[0]') | Select-Object -Last 1)
if ($taskMajor -lt 22) { throw 'Web build needs Node.js 22.13+ or 24. DevEco bundled Node 18 is for Hvigor only. Supply -NodePath.' }
Push-Location (Join-Path $taskRoot 'web')
try {
 if ($Install -or !(Test-Path 'node_modules/vite')) {
  $taskNpm = Join-Path (Split-Path $taskNode) 'node_modules/npm/bin/npm-cli.js'
  if ($NpmCliPath) { $taskNpm = $NpmCliPath }
  if (!(Test-Path $taskNpm)) { throw 'npm CLI not found beside Node. Install a full Node.js distribution or supply -NpmCliPath <npm/bin/npm-cli.js>.' }
  $taskOldPath = $env:Path
  try { $env:Path = (Split-Path $taskNode) + ';' + $taskOldPath; & $taskNode $taskNpm ci --no-audit --no-fund }
  finally { $env:Path = $taskOldPath }
  if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
 }
 & $taskNode node_modules/typescript/bin/tsc --noEmit
 if ($LASTEXITCODE -ne 0) { throw 'Web type check failed' }
 & $taskNode node_modules/vite/bin/vite.js build
 if ($LASTEXITCODE -ne 0) { throw 'Vite build failed' }
 & $taskNode (Join-Path $PSScriptRoot 'prepare-web.mjs')
 if ($LASTEXITCODE -ne 0) { throw 'Asset copy failed' }
} finally { Pop-Location }
