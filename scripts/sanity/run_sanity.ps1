#
# Sanity Test Script for Netflix OSS Stack (PowerShell version)
# Runs REST, SOAP, and GraphQL tests via Gateway
#

param(
    [Parameter(Mandatory=$true)]
    [string]$GatewayIP
)

$ErrorActionPreference = "Continue"

$GatewayURL = "http://${GatewayIP}:8080"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportsDir = Join-Path (Split-Path -Parent (Split-Path -Parent $ScriptDir)) "reports"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Results tracking
$TestResults = @{}
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

# Ensure reports directory exists
New-Item -ItemType Directory -Force -Path $ReportsDir | Out-Null

function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Pass { param($msg) Write-Host "[PASS] $msg" -ForegroundColor Green }
function Write-Fail { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

function Record-Result {
    param($TestName, $Passed, $Response, $Error)
    
    $script:TotalTests++
    
    if ($Passed) {
        $script:PassedTests++
        Write-Pass $TestName
        $script:TestResults[$TestName] = "PASS"
    } else {
        $script:FailedTests++
        Write-Fail "${TestName}: $Error"
        $script:TestResults[$TestName] = "FAIL: $Error"
    }
}

function Wait-ForGateway {
    Write-Info "Waiting for Gateway at ${GatewayURL}..."
    
    for ($i = 1; $i -le 30; $i++) {
        try {
            $response = Invoke-RestMethod -Uri "${GatewayURL}/actuator/health" -TimeoutSec 10 -ErrorAction SilentlyContinue
            if ($response.status -eq "UP") {
                Write-Pass "Gateway is UP!"
                return $true
            }
        } catch {
            Write-Host "  Waiting... ($i/30)"
            Start-Sleep -Seconds 10
        }
    }
    Write-Fail "Gateway not available after 5 minutes"
    return $false
}

function Test-RestApi {
    Write-Info "Testing REST API: POST /api/rest/echo"
    
    $body = @{
        type = "REST_TEST"
        message = "Hello from sanity test"
        amount = 123.45
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "${GatewayURL}/api/rest/echo" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
        
        if ($response.clientCertSubject -and $response.clientCertSerial -and $response.backendResponse.computedOutput) {
            Record-Result "REST_API" $true $response ""
            Write-Host "  Response: $($response | ConvertTo-Json -Compress)"
            return $true
        } else {
            Record-Result "REST_API" $false $response "mTLS verification failed - missing cert info"
        }
    } catch {
        Record-Result "REST_API" $false "" $_.Exception.Message
    }
    return $false
}

function Test-SoapApi {
    Write-Info "Testing SOAP API: POST /ws"
    
    $soapRequest = @"
<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                  xmlns:soap="http://netflix.oss.stack/bff/soap">
   <soapenv:Header/>
   <soapenv:Body>
      <soap:ProcessRequestMessage>
         <soap:type>SOAP_TEST</soap:type>
         <soap:message>Hello from SOAP sanity test</soap:message>
         <soap:amount>456.78</soap:amount>
      </soap:ProcessRequestMessage>
   </soapenv:Body>
</soapenv:Envelope>
"@
    
    try {
        $headers = @{
            "SOAPAction" = "ProcessRequest"
        }
        $response = Invoke-WebRequest -Uri "${GatewayURL}/ws" -Method Post -Body $soapRequest -ContentType "text/xml" -Headers $headers -TimeoutSec 30
        
        if ($response.Content -match "clientCertSubject" -and $response.Content -match "clientCertSerial" -and $response.Content -match "computedOutput") {
            Record-Result "SOAP_API" $true $response.Content ""
            Write-Host "  Response contains valid SOAP envelope with mTLS verification"
            return $true
        } else {
            Record-Result "SOAP_API" $false $response.Content "mTLS verification failed - missing cert info"
        }
    } catch {
        Record-Result "SOAP_API" $false "" $_.Exception.Message
    }
    return $false
}

function Test-GraphqlApi {
    Write-Info "Testing GraphQL API: POST /graphql"
    
    $graphqlRequest = @{
        query = 'mutation { process(type: "GRAPHQL_TEST", message: "Hello from GraphQL sanity test", amount: 789.01) { requestId originalType originalMessage originalAmount computedOutput processedBy instanceInfo timestamp clientCertSubject clientCertSerial middlewareProcessed } }'
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "${GatewayURL}/graphql" -Method Post -Body $graphqlRequest -ContentType "application/json" -TimeoutSec 30
        
        $data = $response.data.process
        if ($data.clientCertSubject -and $data.clientCertSerial -and $data.computedOutput) {
            Record-Result "GRAPHQL_API" $true $response ""
            Write-Host "  Response: $($response | ConvertTo-Json -Compress)"
            return $true
        } else {
            Record-Result "GRAPHQL_API" $false $response "mTLS verification failed - missing cert info"
        }
    } catch {
        Record-Result "GRAPHQL_API" $false "" $_.Exception.Message
    }
    return $false
}

function Test-GatewayHealth {
    Write-Info "Testing Gateway Health Endpoint"
    
    try {
        $response = Invoke-RestMethod -Uri "${GatewayURL}/actuator/health" -TimeoutSec 10
        if ($response.status -eq "UP") {
            Record-Result "GATEWAY_HEALTH" $true $response ""
            return $true
        } else {
            Record-Result "GATEWAY_HEALTH" $false $response "Gateway not healthy"
        }
    } catch {
        Record-Result "GATEWAY_HEALTH" $false "" $_.Exception.Message
    }
    return $false
}

function Generate-JsonReport {
    $report = @{
        timestamp = (Get-Date -Format "o")
        gateway_url = $GatewayURL
        summary = @{
            total_tests = $TotalTests
            passed = $PassedTests
            failed = $FailedTests
            pass_rate = if ($TotalTests -gt 0) { "{0:P0}" -f ($PassedTests / $TotalTests) } else { "N/A" }
        }
        tests = @{
            gateway_health = @{
                name = "Gateway Health Check"
                result = if ($TestResults["GATEWAY_HEALTH"] -eq "PASS") { "PASS" } else { "FAIL" }
            }
            rest_api = @{
                name = "REST API Test"
                endpoint = "POST /api/rest/echo"
                result = if ($TestResults["REST_API"] -eq "PASS") { "PASS" } else { "FAIL" }
                mtls_verified = $TestResults["REST_API"] -eq "PASS"
            }
            soap_api = @{
                name = "SOAP API Test"
                endpoint = "POST /ws"
                result = if ($TestResults["SOAP_API"] -eq "PASS") { "PASS" } else { "FAIL" }
                mtls_verified = $TestResults["SOAP_API"] -eq "PASS"
            }
            graphql_api = @{
                name = "GraphQL API Test"
                endpoint = "POST /graphql"
                result = if ($TestResults["GRAPHQL_API"] -eq "PASS") { "PASS" } else { "FAIL" }
                mtls_verified = $TestResults["GRAPHQL_API"] -eq "PASS"
            }
        }
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $ReportsDir "sanity-report.json") -Encoding UTF8
    Write-Info "JSON report generated: $ReportsDir\sanity-report.json"
}

function Generate-HtmlReport {
    $statusColor = if ($FailedTests -eq 0) { "#4CAF50" } else { "#f44336" }
    $statusText = if ($FailedTests -eq 0) { "ALL TESTS PASSED" } else { "SOME TESTS FAILED" }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Netflix OSS Stack - Sanity Test Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #e94560; text-align: center; }
        .status-banner { background: $statusColor; color: white; padding: 20px; text-align: center; border-radius: 8px; font-size: 1.5em; margin: 20px 0; }
        .summary { display: flex; justify-content: space-around; margin: 20px 0; }
        .summary-card { background: #16213e; padding: 20px; border-radius: 8px; text-align: center; min-width: 150px; }
        .summary-card .value { font-size: 2em; color: #e94560; }
        .test-section { background: #16213e; border-radius: 8px; margin: 15px 0; }
        .test-header { background: #0f3460; padding: 15px; display: flex; justify-content: space-between; }
        .test-status { padding: 5px 15px; border-radius: 20px; }
        .test-status.pass { background: #4CAF50; }
        .test-status.fail { background: #f44336; }
        .test-body { padding: 20px; }
        .timestamp { text-align: center; color: #666; margin-top: 30px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Netflix OSS Stack - Sanity Test Report</h1>
        <div class="status-banner">$statusText</div>
        <div class="summary">
            <div class="summary-card"><h3>Total</h3><div class="value">$TotalTests</div></div>
            <div class="summary-card"><h3>Passed</h3><div class="value" style="color:#4CAF50">$PassedTests</div></div>
            <div class="summary-card"><h3>Failed</h3><div class="value" style="color:#f44336">$FailedTests</div></div>
        </div>
        <div class="test-section">
            <div class="test-header">
                <h3>Gateway Health</h3>
                <span class="test-status $(if($TestResults['GATEWAY_HEALTH'] -eq 'PASS'){'pass'}else{'fail'})">$($TestResults['GATEWAY_HEALTH'])</span>
            </div>
        </div>
        <div class="test-section">
            <div class="test-header">
                <h3>REST API</h3>
                <span class="test-status $(if($TestResults['REST_API'] -eq 'PASS'){'pass'}else{'fail'})">$($TestResults['REST_API'])</span>
            </div>
        </div>
        <div class="test-section">
            <div class="test-header">
                <h3>SOAP API</h3>
                <span class="test-status $(if($TestResults['SOAP_API'] -eq 'PASS'){'pass'}else{'fail'})">$($TestResults['SOAP_API'])</span>
            </div>
        </div>
        <div class="test-section">
            <div class="test-header">
                <h3>GraphQL API</h3>
                <span class="test-status $(if($TestResults['GRAPHQL_API'] -eq 'PASS'){'pass'}else{'fail'})">$($TestResults['GRAPHQL_API'])</span>
            </div>
        </div>
        <p class="timestamp">Report generated: $(Get-Date)</p>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath (Join-Path $ReportsDir "sanity-report.html") -Encoding UTF8
    Write-Info "HTML report generated: $ReportsDir\sanity-report.html"
}

# Main
Write-Host ""
Write-Host "========================================"
Write-Host "  Netflix OSS Stack - Sanity Tests"
Write-Host "  Gateway: $GatewayURL"
Write-Host "  Timestamp: $(Get-Date)"
Write-Host "========================================"
Write-Host ""

if (-not (Wait-ForGateway)) {
    exit 1
}

Write-Host ""
Write-Info "Running sanity tests..."
Write-Host ""

Test-GatewayHealth | Out-Null
Test-RestApi | Out-Null
Test-SoapApi | Out-Null
Test-GraphqlApi | Out-Null

Write-Host ""
Write-Host "========================================"
Write-Host "  Test Summary"
Write-Host "========================================"
Write-Host "  Total: $TotalTests"
Write-Host "  Passed: $PassedTests"
Write-Host "  Failed: $FailedTests"
Write-Host "========================================"
Write-Host ""

Generate-JsonReport
Generate-HtmlReport

if ($FailedTests -gt 0) {
    Write-Warn "Some tests failed. Check reports for details."
    exit 1
} else {
    Write-Pass "All sanity tests passed!"
    exit 0
}
