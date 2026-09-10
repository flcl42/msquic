<#

.SYNOPSIS
Runs the BBRv3 comparison matrix over the existing DuoNic emulated WAN harness.

.DESCRIPTION
This wrapper exercises the two existing MsQuic congestion controllers and the
new BBRv3 controller across deterministic environments, including cases where
model-based BBR is expected to have a useful advantage over loss-based CUBIC
or where BBRv3 should improve BBRv1 behavior:

  - RegularMidLatency: mid-latency, mid-throughput, no random loss.
  - FixedSeedRandomThroughput: a fixed-seed spread of bottleneck rates.
  - ModeratePacketLoss: mid-latency, mid-throughput, moderate random loss.
  - RandomLossSweep: non-congestion random loss at several loss rates.
  - ShallowBuffer: high-BDP path with queues below one BDP.
  - ShallowBufferWithLoss: shallow queues plus random loss.
  - HighBdpRandomLoss: long-RTT/high-throughput path with random loss.

The script delegates to scripts/emulated-performance.ps1, so it has the same
requirements: DuoNic must be installed and secnetperf must already be built.
Only QUIC is supported because TCP uses the operating system's congestion
controller and cannot exercise the MsQuic controllers in this comparison.

#>

param (
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "Release")]
    [string]$Config = "Release",

    [Parameter(Mandatory = $false)]
    [ValidateSet("x86", "x64", "arm", "arm64")]
    [string]$Arch = "x64",

    [Parameter(Mandatory = $false)]
    [ValidateSet("schannel", "quictls", "openssl", "")]
    [string]$Tls = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("QUIC")]
    [string[]]$Protocol = "QUIC",

    [Parameter(Mandatory = $false)]
    [ValidateSet("RegularMidLatency", "FixedSeedRandomThroughput", "ModeratePacketLoss", "RandomLossSweep", "ShallowBuffer", "ShallowBufferWithLoss", "HighBdpRandomLoss", "All")]
    [string[]]$Scenario = "All",

    [Parameter(Mandatory = $false)]
    [ValidateSet("cubic", "bbr", "bbrv3")]
    [string[]]$CongestionControl = ("cubic", "bbr", "bbrv3"),

    [Parameter(Mandatory = $false)]
    [Int32[]]$DurationMs = 15000,

    [Parameter(Mandatory = $false)]
    [Int32[]]$Pacing = 1,

    [Parameter(Mandatory = $false)]
    [Int32]$NumIterations = 3,

    [Parameter(Mandatory = $false)]
    [ValidateSet("None", "Datapath.Light", "Datapath.Verbose", "Performance.Light", "Performance.Verbose", "Full.Light", "Full.Verbose")]
    [string]$LogProfile = "None",

    [Parameter(Mandatory = $false)]
    [switch]$PrintConnectionStats = $false,

    [Parameter(Mandatory = $false)]
    [switch]$NoDateLogDir = $false
)

Set-StrictMode -Version 'Latest'
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'

$EmulatedPerformance = Join-Path $PSScriptRoot "emulated-performance.ps1"

$ScenarioSpecs = @{
    RegularMidLatency = @{
        RttMs = @(60)
        BottleneckMbps = @(50)
        BottleneckQueueRatio = @(1.0)
        RandomLossDenominator = @(0)
        BaseRandomSeed = "00112233445566778899aabbccddee"
    }
    FixedSeedRandomThroughput = @{
        RttMs = @(80)
        BottleneckMbps = @(12, 26, 44, 18, 36)
        BottleneckQueueRatio = @(1.0)
        RandomLossDenominator = @(0)
        BaseRandomSeed = "7a13d20cb45e9108ac6534d99f20aa"
    }
    ModeratePacketLoss = @{
        RttMs = @(60)
        BottleneckMbps = @(50)
        BottleneckQueueRatio = @(1.0)
        RandomLossDenominator = @(200)
        BaseRandomSeed = "c0ffee1234567890abcddcba098765"
    }
    RandomLossSweep = @{
        RttMs = @(60)
        BottleneckMbps = @(50)
        BottleneckQueueRatio = @(1.0)
        RandomLossDenominator = @(1000, 500, 200)
        BaseRandomSeed = "e2e1f00d1234567890abcddcba0987"
    }
    ShallowBuffer = @{
        RttMs = @(80)
        BottleneckMbps = @(50)
        BottleneckQueueRatio = @(0.125, 0.25, 0.5)
        RandomLossDenominator = @(0)
        BaseRandomSeed = "5aa1100b1234567890abcddcba0987"
    }
    ShallowBufferWithLoss = @{
        RttMs = @(80)
        BottleneckMbps = @(50)
        BottleneckQueueRatio = @(0.25, 0.5)
        RandomLossDenominator = @(500, 200)
        BaseRandomSeed = "1055b0ff1234567890abcddcba0987"
    }
    HighBdpRandomLoss = @{
        RttMs = @(100)
        BottleneckMbps = @(100)
        BottleneckQueueRatio = @(1.0)
        RandomLossDenominator = @(1000, 500)
        BaseRandomSeed = "b16bd0001234567890abcddcba0987"
    }
}

if ($Scenario -contains "All") {
    $Scenario = @("RegularMidLatency", "FixedSeedRandomThroughput", "ModeratePacketLoss", "RandomLossSweep", "ShallowBuffer", "ShallowBufferWithLoss", "HighBdpRandomLoss")
}

foreach ($ScenarioName in $Scenario) {
    $Spec = $ScenarioSpecs[$ScenarioName]
    if ($null -eq $Spec) {
        throw "Unknown BBRv3 benchmark scenario: $ScenarioName"
    }

    Write-Host "Running BBRv3 benchmark scenario: $ScenarioName"

    & $EmulatedPerformance `
        -Config $Config `
        -Arch $Arch `
        -Tls $Tls `
        -Protocol $Protocol `
        -RttMs $Spec["RttMs"] `
        -BottleneckMbps $Spec["BottleneckMbps"] `
        -BottleneckQueueRatio $Spec["BottleneckQueueRatio"] `
        -RandomLossDenominator $Spec["RandomLossDenominator"] `
        -BaseRandomSeed $Spec["BaseRandomSeed"] `
        -DurationMs $DurationMs `
        -Pacing $Pacing `
        -NumIterations $NumIterations `
        -LogProfile $LogProfile `
        -ScenarioName $ScenarioName `
        -PrintConnectionStats:$PrintConnectionStats `
        -CongestionControl $CongestionControl `
        -NoDateLogDir:$NoDateLogDir
}
