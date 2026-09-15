[CmdletBinding()]
param([int]$TimeoutSeconds = 270)

$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $PSScriptRoot
$testConfig = Join-Path $testRoot 'tests/wezterm_live_test.lua'
$testToken = [guid]::NewGuid().ToString('N')
$testLogs = New-Item -ItemType Directory -Path ([IO.Path]::Combine([IO.Path]::GetTempPath(), "wezterm-statusline-live-$testToken"))
$testLog = Join-Path $testLogs.FullName 'stderr.log'
$testExe = (Get-Command wezterm-gui -ErrorAction Stop).Source
$testProcess = Start-Process -FilePath $testExe -ArgumentList @(
  '--config-file', ('"' + $testConfig + '"'), 'start', '--always-new-process', '--class', "statusline-live-$testToken"
) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testLogs.FullName 'stdout.log') -RedirectStandardError $testLog -PassThru
Write-Output "Isolated GUI PID: $($testProcess.Id); log: $testLog"
try {
  $testDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $testDeadline -and -not $testProcess.HasExited) {
    Start-Sleep -Seconds 1
    $testContent = Get-Content -LiteralPath $testLog -Raw -ErrorAction SilentlyContinue
    if ($testContent -match 'LIVE_TEST_RESULT (\{[^\r\n]+\})') {
      $testResult = $Matches[1] | ConvertFrom-Json
      $testResult | ConvertTo-Json
      if (-not $testResult.passed) { throw $testResult.message }
      if ($testContent -match '(?m)ERROR[^\r\n]*codex_statusline:') {
        throw "Runtime error in $testLog"
      }
      return
    }
  }
  throw "GUI test did not complete. Inspect $testLog"
} finally {
  if (-not $testProcess.HasExited) {
    # This Process handle was created above, never resolved from a user window.
    $testProcess.Kill($true)
    $testProcess.WaitForExit()
  }
}
