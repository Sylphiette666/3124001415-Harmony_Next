param([int]$Port = 8766)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try {
  if (!(Test-Path -LiteralPath '.venv/Scripts/python.exe')) { python -m venv .venv }
  & ./.venv/Scripts/python.exe -m pip install -r server/requirements.txt
  if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }
  & ./.venv/Scripts/python.exe -m server.manage demo --seed
  if ($LASTEXITCODE -ne 0) { throw 'Server initialization failed.' }
  & ./.venv/Scripts/python.exe -m uvicorn server.app:app_factory --factory --host 127.0.0.1 --port $Port
} finally { Pop-Location }
