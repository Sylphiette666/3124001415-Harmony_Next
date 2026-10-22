param(
  [string]$PythonPath = 'python',
  [int]$Port = 8765,
  [string]$DeviceId = ''
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $taskRoot
try {
  $taskVenv = Join-Path $taskRoot '.venv\Scripts\python.exe'
  if (!(Test-Path -LiteralPath $taskVenv)) {
    & $PythonPath -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Python 3.10+ venv creation failed.' }
    & $taskVenv -m pip install -r server/requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Backend dependency installation failed.' }
  }
  & $taskVenv -m server.manage init
  if ($LASTEXITCODE -ne 0) { throw 'Server initialization failed.' }
  if ($DeviceId) {
    & $taskVenv -m server.manage provision --device-id $DeviceId
    if ($LASTEXITCODE -ne 0) { throw 'Device provisioning failed.' }
  }
  if (!(Test-Path -LiteralPath '.local\model.json')) {
    & $taskVenv -m server.manage publish --version 1.0.0
    if ($LASTEXITCODE -ne 0) { throw 'Model publishing failed.' }
  }
  & $taskVenv -m uvicorn server.app:app_factory --factory --host 127.0.0.1 --port $Port
} finally { Pop-Location }
