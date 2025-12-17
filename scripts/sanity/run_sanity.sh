#!/bin/bash
#
# Sanity Test Script for Netflix OSS Stack
# Runs REST, SOAP, and GraphQL tests via Gateway
#

set -e

GATEWAY_IP="${1:-localhost}"
GATEWAY_URL="http://${GATEWAY_IP}:8080"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${SCRIPT_DIR}/../../reports"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Results tracking
declare -A TEST_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

mkdir -p "$REPORTS_DIR"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

record_result() {
    local test_name="$1"
    local passed="$2"
    local response="$3"
    local error="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$passed" = "true" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_pass "$test_name"
        TEST_RESULTS["$test_name"]="PASS"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_fail "$test_name: $error"
        TEST_RESULTS["$test_name"]="FAIL: $error"
    fi
}

# Wait for Gateway
wait_for_gateway() {
    log_info "Waiting for Gateway at ${GATEWAY_URL}..."
    for i in {1..30}; do
        if curl -s "${GATEWAY_URL}/actuator/health" 2>/dev/null | grep -q '"status":"UP"'; then
            log_pass "Gateway is UP!"
            return 0
        fi
        echo "  Waiting... ($i/30)"
        sleep 10
    done
    log_fail "Gateway not available after 5 minutes"
    return 1
}

# Test 1: REST API
test_rest_api() {
    log_info "Testing REST API: POST /api/rest/echo"
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "${GATEWAY_URL}/api/rest/echo" \
        -H "Content-Type: application/json" \
        -d '{"type":"REST_TEST","message":"Hello from sanity test","amount":123.45}' 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        # Check for mTLS proof (client cert subject and serial)
        if echo "$body" | grep -q "clientCertSubject" && echo "$body" | grep -q "clientCertSerial"; then
            if echo "$body" | grep -q "computedOutput"; then
                record_result "REST_API" "true" "$body" ""
                echo "  Response: $(echo $body | jq -c '.' 2>/dev/null || echo $body)"
                return 0
            else
                record_result "REST_API" "false" "$body" "Missing computedOutput in response"
            fi
        else
            record_result "REST_API" "false" "$body" "mTLS verification failed - missing cert info"
        fi
    else
        record_result "REST_API" "false" "$body" "HTTP $http_code"
    fi
    return 1
}

# Test 2: SOAP API
test_soap_api() {
    log_info "Testing SOAP API: POST /ws"
    
    local soap_request='<?xml version="1.0" encoding="UTF-8"?>
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
</soapenv:Envelope>'
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "${GATEWAY_URL}/ws" \
        -H "Content-Type: text/xml" \
        -H "SOAPAction: \"ProcessRequest\"" \
        -d "$soap_request" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        # Check for mTLS proof in SOAP response
        if echo "$body" | grep -q "clientCertSubject" && echo "$body" | grep -q "clientCertSerial"; then
            if echo "$body" | grep -q "computedOutput"; then
                record_result "SOAP_API" "true" "$body" ""
                echo "  Response contains valid SOAP envelope with mTLS verification"
                return 0
            else
                record_result "SOAP_API" "false" "$body" "Missing computedOutput in response"
            fi
        else
            record_result "SOAP_API" "false" "$body" "mTLS verification failed - missing cert info"
        fi
    else
        record_result "SOAP_API" "false" "$body" "HTTP $http_code"
    fi
    return 1
}

# Test 3: GraphQL API
test_graphql_api() {
    log_info "Testing GraphQL API: POST /graphql"
    
    local graphql_request='{
        "query": "mutation { process(type: \"GRAPHQL_TEST\", message: \"Hello from GraphQL sanity test\", amount: 789.01) { requestId originalType originalMessage originalAmount computedOutput processedBy instanceInfo timestamp clientCertSubject clientCertSerial middlewareProcessed } }"
    }'
    
    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "${GATEWAY_URL}/graphql" \
        -H "Content-Type: application/json" \
        -d "$graphql_request" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        # Check for mTLS proof
        if echo "$body" | grep -q "clientCertSubject" && echo "$body" | grep -q "clientCertSerial"; then
            if echo "$body" | grep -q "computedOutput"; then
                record_result "GRAPHQL_API" "true" "$body" ""
                echo "  Response: $(echo $body | jq -c '.' 2>/dev/null || echo $body)"
                return 0
            else
                record_result "GRAPHQL_API" "false" "$body" "Missing computedOutput in response"
            fi
        else
            record_result "GRAPHQL_API" "false" "$body" "mTLS verification failed - missing cert info"
        fi
    else
        record_result "GRAPHQL_API" "false" "$body" "HTTP $http_code"
    fi
    return 1
}

# Test 4: Gateway Health
test_gateway_health() {
    log_info "Testing Gateway Health Endpoint"
    
    local response
    response=$(curl -s -w "\n%{http_code}" "${GATEWAY_URL}/actuator/health" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ] && echo "$body" | grep -q '"status":"UP"'; then
        record_result "GATEWAY_HEALTH" "true" "$body" ""
        return 0
    else
        record_result "GATEWAY_HEALTH" "false" "$body" "Gateway not healthy"
        return 1
    fi
}

# Generate JSON Report
generate_json_report() {
    local rest_result="${TEST_RESULTS[REST_API]:-NOT_RUN}"
    local soap_result="${TEST_RESULTS[SOAP_API]:-NOT_RUN}"
    local graphql_result="${TEST_RESULTS[GRAPHQL_API]:-NOT_RUN}"
    local gateway_result="${TEST_RESULTS[GATEWAY_HEALTH]:-NOT_RUN}"
    
    cat > "${REPORTS_DIR}/sanity-report.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "gateway_url": "${GATEWAY_URL}",
    "summary": {
        "total_tests": ${TOTAL_TESTS},
        "passed": ${PASSED_TESTS},
        "failed": ${FAILED_TESTS},
        "pass_rate": "$(echo "scale=2; ${PASSED_TESTS}*100/${TOTAL_TESTS}" | bc 2>/dev/null || echo "N/A")%"
    },
    "tests": {
        "gateway_health": {
            "name": "Gateway Health Check",
            "result": "$(echo $gateway_result | cut -d: -f1)",
            "details": "$gateway_result"
        },
        "rest_api": {
            "name": "REST API Test",
            "endpoint": "POST /api/rest/echo",
            "result": "$(echo $rest_result | cut -d: -f1)",
            "details": "$rest_result",
            "mtls_verified": $([ "$rest_result" = "PASS" ] && echo "true" || echo "false")
        },
        "soap_api": {
            "name": "SOAP API Test",
            "endpoint": "POST /ws",
            "result": "$(echo $soap_result | cut -d: -f1)",
            "details": "$soap_result",
            "mtls_verified": $([ "$soap_result" = "PASS" ] && echo "true" || echo "false")
        },
        "graphql_api": {
            "name": "GraphQL API Test",
            "endpoint": "POST /graphql",
            "result": "$(echo $graphql_result | cut -d: -f1)",
            "details": "$graphql_result",
            "mtls_verified": $([ "$graphql_result" = "PASS" ] && echo "true" || echo "false")
        }
    },
    "flow_verification": {
        "client_to_gateway": true,
        "gateway_to_bff": $([ "$rest_result" = "PASS" ] && echo "true" || echo "false"),
        "bff_to_middleware_mtls": $([ "$rest_result" = "PASS" ] && echo "true" || echo "false"),
        "middleware_to_backend": $([ "$rest_result" = "PASS" ] && echo "true" || echo "false")
    }
}
EOF
    log_info "JSON report generated: ${REPORTS_DIR}/sanity-report.json"
}

# Generate HTML Report
generate_html_report() {
    local status_color=$( [ $FAILED_TESTS -eq 0 ] && echo "#4CAF50" || echo "#f44336" )
    local status_text=$( [ $FAILED_TESTS -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED" )
    
    cat > "${REPORTS_DIR}/sanity-report.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Netflix OSS Stack - Sanity Test Report</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 { color: #e94560; margin-bottom: 20px; text-align: center; }
        .status-banner { background: ${status_color}; color: white; padding: 20px; text-align: center; border-radius: 8px; margin-bottom: 20px; font-size: 1.5em; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .summary-card { background: #16213e; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card h3 { color: #0f3460; margin-bottom: 10px; }
        .summary-card .value { font-size: 2em; font-weight: bold; color: #e94560; }
        .test-section { background: #16213e; border-radius: 8px; margin-bottom: 15px; overflow: hidden; }
        .test-header { background: #0f3460; padding: 15px 20px; display: flex; justify-content: space-between; align-items: center; }
        .test-header h3 { color: #eee; }
        .test-status { padding: 5px 15px; border-radius: 20px; font-weight: bold; }
        .test-status.pass { background: #4CAF50; color: white; }
        .test-status.fail { background: #f44336; color: white; }
        .test-body { padding: 20px; }
        .test-detail { margin-bottom: 10px; }
        .test-detail label { color: #888; display: block; margin-bottom: 5px; }
        .test-detail code { background: #0f3460; padding: 10px; border-radius: 4px; display: block; overflow-x: auto; }
        .flow-diagram { background: #0f3460; padding: 20px; border-radius: 8px; margin-top: 20px; }
        .flow-diagram h3 { margin-bottom: 15px; color: #e94560; }
        .flow { display: flex; align-items: center; justify-content: center; flex-wrap: wrap; gap: 10px; }
        .flow-item { background: #16213e; padding: 10px 20px; border-radius: 4px; }
        .flow-arrow { color: #4CAF50; font-size: 1.5em; }
        .timestamp { text-align: center; color: #666; margin-top: 30px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎬 Netflix OSS Stack - Sanity Test Report</h1>
        
        <div class="status-banner">${status_text}</div>
        
        <div class="summary">
            <div class="summary-card">
                <h3>Total Tests</h3>
                <div class="value">${TOTAL_TESTS}</div>
            </div>
            <div class="summary-card">
                <h3>Passed</h3>
                <div class="value" style="color: #4CAF50;">${PASSED_TESTS}</div>
            </div>
            <div class="summary-card">
                <h3>Failed</h3>
                <div class="value" style="color: #f44336;">${FAILED_TESTS}</div>
            </div>
            <div class="summary-card">
                <h3>Gateway URL</h3>
                <div class="value" style="font-size: 0.8em;">${GATEWAY_URL}</div>
            </div>
        </div>

        <div class="test-section">
            <div class="test-header">
                <h3>🔗 Gateway Health Check</h3>
                <span class="test-status $( [ "${TEST_RESULTS[GATEWAY_HEALTH]}" = "PASS" ] && echo "pass" || echo "fail" )">
                    ${TEST_RESULTS[GATEWAY_HEALTH]:-NOT_RUN}
                </span>
            </div>
            <div class="test-body">
                <div class="test-detail">
                    <label>Endpoint</label>
                    <code>GET ${GATEWAY_URL}/actuator/health</code>
                </div>
            </div>
        </div>

        <div class="test-section">
            <div class="test-header">
                <h3>🌐 REST API Test</h3>
                <span class="test-status $( [ "${TEST_RESULTS[REST_API]}" = "PASS" ] && echo "pass" || echo "fail" )">
                    ${TEST_RESULTS[REST_API]:-NOT_RUN}
                </span>
            </div>
            <div class="test-body">
                <div class="test-detail">
                    <label>Endpoint</label>
                    <code>POST ${GATEWAY_URL}/api/rest/echo</code>
                </div>
                <div class="test-detail">
                    <label>Request Body</label>
                    <code>{"type":"REST_TEST","message":"Hello from sanity test","amount":123.45}</code>
                </div>
                <div class="test-detail">
                    <label>mTLS Verification</label>
                    <code>$( [ "${TEST_RESULTS[REST_API]}" = "PASS" ] && echo "✅ Client certificate verified by middleware" || echo "❌ mTLS verification failed" )</code>
                </div>
            </div>
        </div>

        <div class="test-section">
            <div class="test-header">
                <h3>📦 SOAP API Test</h3>
                <span class="test-status $( [ "${TEST_RESULTS[SOAP_API]}" = "PASS" ] && echo "pass" || echo "fail" )">
                    ${TEST_RESULTS[SOAP_API]:-NOT_RUN}
                </span>
            </div>
            <div class="test-body">
                <div class="test-detail">
                    <label>Endpoint</label>
                    <code>POST ${GATEWAY_URL}/ws</code>
                </div>
                <div class="test-detail">
                    <label>SOAP Operation</label>
                    <code>ProcessRequest(type, message, amount)</code>
                </div>
                <div class="test-detail">
                    <label>mTLS Verification</label>
                    <code>$( [ "${TEST_RESULTS[SOAP_API]}" = "PASS" ] && echo "✅ Client certificate verified by middleware" || echo "❌ mTLS verification failed" )</code>
                </div>
            </div>
        </div>

        <div class="test-section">
            <div class="test-header">
                <h3>⚡ GraphQL API Test</h3>
                <span class="test-status $( [ "${TEST_RESULTS[GRAPHQL_API]}" = "PASS" ] && echo "pass" || echo "fail" )">
                    ${TEST_RESULTS[GRAPHQL_API]:-NOT_RUN}
                </span>
            </div>
            <div class="test-body">
                <div class="test-detail">
                    <label>Endpoint</label>
                    <code>POST ${GATEWAY_URL}/graphql</code>
                </div>
                <div class="test-detail">
                    <label>GraphQL Mutation</label>
                    <code>process(type: String!, message: String!, amount: Float!): ProcessedResponse</code>
                </div>
                <div class="test-detail">
                    <label>mTLS Verification</label>
                    <code>$( [ "${TEST_RESULTS[GRAPHQL_API]}" = "PASS" ] && echo "✅ Client certificate verified by middleware" || echo "❌ mTLS verification failed" )</code>
                </div>
            </div>
        </div>

        <div class="flow-diagram">
            <h3>🔄 Request Flow (Verified by mTLS)</h3>
            <div class="flow">
                <div class="flow-item">Client</div>
                <span class="flow-arrow">→</span>
                <div class="flow-item">Gateway:8080</div>
                <span class="flow-arrow">→</span>
                <div class="flow-item">User-BFF:8081</div>
                <span class="flow-arrow" style="color: #e94560;">🔐→</span>
                <div class="flow-item">mTLS-Middleware:8443</div>
                <span class="flow-arrow">→</span>
                <div class="flow-item">Core-Backend:8082</div>
            </div>
            <p style="text-align: center; margin-top: 15px; color: #888;">
                🔐 indicates mTLS encrypted connection with client certificate verification
            </p>
        </div>

        <p class="timestamp">Report generated: $(date)</p>
    </div>
</body>
</html>
EOF
    log_info "HTML report generated: ${REPORTS_DIR}/sanity-report.html"
}

# Main
main() {
    echo ""
    echo "========================================"
    echo "  Netflix OSS Stack - Sanity Tests"
    echo "  Gateway: ${GATEWAY_URL}"
    echo "  Timestamp: $(date)"
    echo "========================================"
    echo ""
    
    wait_for_gateway || exit 1
    
    echo ""
    log_info "Running sanity tests..."
    echo ""
    
    test_gateway_health || true
    test_rest_api || true
    test_soap_api || true
    test_graphql_api || true
    
    echo ""
    echo "========================================"
    echo "  Test Summary"
    echo "========================================"
    echo "  Total: ${TOTAL_TESTS}"
    echo "  Passed: ${PASSED_TESTS}"
    echo "  Failed: ${FAILED_TESTS}"
    echo "========================================"
    echo ""
    
    generate_json_report
    generate_html_report
    
    if [ $FAILED_TESTS -gt 0 ]; then
        log_warn "Some tests failed. Check reports for details."
        exit 1
    else
        log_pass "All sanity tests passed!"
        exit 0
    fi
}

main "$@"
