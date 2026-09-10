<#
.SYNOPSIS
Validates the emulated WAN benchmark's parameter forwarding and result handling
without starting secnetperf or changing network adapters. Requires PowerShell 7.
#>

Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'

$HarnessPath = Join-Path $PSScriptRoot "emulated-performance.ps1"
$WrapperPath = Join-Path $PSScriptRoot "bbrv3-emulated-benchmark.ps1"
$ParseErrors = $null
$HarnessAst = [System.Management.Automation.Language.Parser]::ParseFile($HarnessPath, [ref]$null, [ref]$ParseErrors)
if ($ParseErrors.Count) { throw $ParseErrors[0] }

# Load only the pure result helpers; none of the harness's setup is executed.
$Helpers = $HarnessAst.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $_.Name -in @("Get-TestScenarioName", "Find-MatchingTest", "Get-ConnectionStatisticValue", "Get-ConnectionStatistics")
}
. ([scriptblock]::Create(($Helpers.Extent.Text -join "`n")))

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) {
        throw "${Message}: expected '$Expected', got '$Actual'."
    }
}

# Use the actual harness parameter declaration so the wrapper must satisfy all
# its validation attributes. Only the hardware-dependent body is replaced.
$HarnessStub = [scriptblock]::Create($HarnessAst.ParamBlock.Extent.Text + "`n[pscustomobject]`$PSBoundParameters")
$Runs = & {
    function Join-Path { $HarnessStub }
    & $WrapperPath
}
Assert-Equal $Runs.Count 7 "All scenarios must run with default arguments"
foreach ($Run in $Runs) {
    Assert-Equal $Run.Tls "" "Default TLS must reach the harness's platform selection"
    Assert-Equal ($Run.CongestionControl -join ',') "cubic,bbr,bbrv3" "Every QUIC controller must be exercised"
    Assert-Equal $Run.BaseRandomSeed.Length 30 "The base seed must leave one byte for the iteration"
    Assert-Equal $Run.NumIterations 3 "Iteration count must be forwarded"
}
$Selected = & {
    function Join-Path { $HarnessStub }
    & $WrapperPath -Scenario ShallowBuffer -Tls schannel -CongestionControl bbrv3 -DurationMs 1234 -PrintConnectionStats
}
Assert-Equal $Selected.ScenarioName "ShallowBuffer" "Scenario selection must be forwarded"
Assert-Equal $Selected.Tls "schannel" "Explicit TLS must be forwarded"
Assert-Equal $Selected.DurationMs[0] 1234 "Duration must be forwarded"
Assert-Equal $Selected.PrintConnectionStats.IsPresent $true "Statistics switch must be forwarded"
$TcpRejected = & {
    function Join-Path { $HarnessStub }
    try {
        $null = & $WrapperPath -Protocol TCPTLS
        $false
    } catch {
        if ($_.FullyQualifiedErrorId -notlike "ParameterArgumentValidationError*") { throw }
        $true
    }
}
Assert-Equal $TcpRejected $true "TCP must not be labeled as a MsQuic controller comparison"

$Current = [pscustomobject]@{
    ScenarioName = "Custom"
    RttMs = 60
    BottleneckMbps = 50
    BottleneckBufferPackets = 275
    RandomLossDenominator = 200
    RandomReorderDenominator = 0
    ReorderDelayDeltaMs = 0
    Tcp = $false
    DurationMs = 15000
    Pacing = $true
    CongestionControl = "bbrv3"
    RateKbps = 40000
}
$Cubic = $Current.PSObject.Copy()
$Cubic.CongestionControl = "cubic"
$Cubic.RateKbps = 10000
$Previous = $Current.PSObject.Copy()
$Previous.RateKbps = 35000
$Match = Find-MatchingTest $Current @($Cubic, $Previous)
Assert-Equal $Match.RateKbps 35000 "Baseline comparison must match the controller"
Assert-Equal (Find-MatchingTest $Current @($Cubic)) $null "An absent controller must have no baseline"

$OtherScenario = $Previous.PSObject.Copy()
$OtherScenario.ScenarioName = "ModeratePacketLoss"
Assert-Equal (Find-MatchingTest $Current @($OtherScenario)) $null "Different scenario seeds must not be compared"
$Legacy = $Previous.PSObject.Copy()
$Legacy.PSObject.Properties.Remove("ScenarioName")
Assert-Equal (Get-TestScenarioName $Legacy) "Custom" "Legacy results must remain mergeable in strict mode"
Assert-Equal (Find-MatchingTest $Current @($Legacy)).RateKbps 35000 "Legacy custom runs must remain comparable"

# These field names and units match QuicPrintConnectionStatistics.
$Stats = Get-ConnectionStatistics @"
Connection Statistics:
  MinRTT                    58000 us
  RTT                       60000 us
  EcnCapable                1
  SendTotalPackets          5000000000
  SendSuspectedLostPackets  42
  SendSpuriousLostPackets   7
  SendCongestionCount       9
  SendEcnCongestionCount    3
  RecvTotalPackets          4000000000
  RecvReorderedPackets      11
  RecvDroppedPackets        12
  RecvDuplicatePackets      13
  RecvDecryptionFailures    0
Result: Upload 40000 kbps.
App Main returning status 0
"@
Assert-Equal $Stats.RttUs 60000 "RTT must not match MinRTT"
Assert-Equal $Stats.MinRttUs 58000 "MinRTT must retain microseconds"
Assert-Equal $Stats.SendTotalPackets 5000000000 "Packet counters must retain 64-bit values"
Assert-Equal $Stats.SendCongestionCount 9 "Congestion counters must be parsed separately from ECN counters"
Assert-Equal $Stats.SendEcnCongestionCount 3 "ECN congestion counters must be retained"
Assert-Equal $Stats.RecvDecryptionFailures 0 "Zero counters must remain zero"
Assert-Equal (Get-ConnectionStatistics "Error: No Successful Connections!") $null "Failed iterations may have no statistics"

Write-Host "Emulated WAN benchmark regression checks passed."
