#!/bin/bash
#
# Certificate Generation Script for mTLS
# Generates Root CA, Server cert for middleware, Client cert for user-bff
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}"
PASSWORD="changeit"
VALIDITY_DAYS=3650

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Clean up previous certificates
cleanup() {
    log_info "Cleaning up previous certificates..."
    rm -f "${CERTS_DIR}"/*.pem "${CERTS_DIR}"/*.p12 "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.srl 2>/dev/null || true
}

# Generate Root CA
generate_root_ca() {
    log_info "Generating Root CA..."
    
    # Generate Root CA private key
    openssl genrsa -out "${CERTS_DIR}/root-ca-key.pem" 4096
    
    # Generate Root CA certificate
    openssl req -x509 -new -nodes \
        -key "${CERTS_DIR}/root-ca-key.pem" \
        -sha256 \
        -days ${VALIDITY_DAYS} \
        -out "${CERTS_DIR}/root-ca.pem" \
        -subj "/C=US/ST=California/L=San Francisco/O=Netflix OSS Stack/OU=DevOps/CN=Root CA"
    
    log_info "Root CA generated successfully"
}

# Generate Middleware Server Certificate
generate_middleware_cert() {
    log_info "Generating Middleware Server certificate..."
    
    # Create config for SAN
    cat > "${CERTS_DIR}/middleware-san.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
ST = California
L = San Francisco
O = Netflix OSS Stack
OU = Middleware
CN = mtls-middleware

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = mtls-middleware
DNS.2 = localhost
DNS.3 = *.compute.amazonaws.com
DNS.4 = *.ec2.internal
IP.1 = 127.0.0.1
EOF

    # Generate private key
    openssl genrsa -out "${CERTS_DIR}/middleware-key.pem" 2048
    
    # Generate CSR
    openssl req -new \
        -key "${CERTS_DIR}/middleware-key.pem" \
        -out "${CERTS_DIR}/middleware.csr" \
        -config "${CERTS_DIR}/middleware-san.cnf"
    
    # Sign with Root CA
    openssl x509 -req \
        -in "${CERTS_DIR}/middleware.csr" \
        -CA "${CERTS_DIR}/root-ca.pem" \
        -CAkey "${CERTS_DIR}/root-ca-key.pem" \
        -CAcreateserial \
        -out "${CERTS_DIR}/middleware-cert.pem" \
        -days ${VALIDITY_DAYS} \
        -sha256 \
        -extensions req_ext \
        -extfile "${CERTS_DIR}/middleware-san.cnf"
    
    # Create PKCS12 keystore for middleware
    openssl pkcs12 -export \
        -in "${CERTS_DIR}/middleware-cert.pem" \
        -inkey "${CERTS_DIR}/middleware-key.pem" \
        -out "${CERTS_DIR}/middleware-keystore.p12" \
        -name "middleware" \
        -CAfile "${CERTS_DIR}/root-ca.pem" \
        -caname "root" \
        -password "pass:${PASSWORD}"
    
    log_info "Middleware server certificate generated successfully"
}

# Generate Client Certificate for User BFF
generate_client_cert() {
    log_info "Generating Client certificate for User BFF..."
    
    # Create config for SAN
    cat > "${CERTS_DIR}/client-san.cnf" << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext

[dn]
C = US
ST = California
L = San Francisco
O = Netflix OSS Stack
OU = UserBFF
CN = user-bff-client

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = user-bff
DNS.2 = localhost
DNS.3 = *.compute.amazonaws.com
DNS.4 = *.ec2.internal
IP.1 = 127.0.0.1
EOF

    # Generate private key
    openssl genrsa -out "${CERTS_DIR}/client-key.pem" 2048
    
    # Generate CSR
    openssl req -new \
        -key "${CERTS_DIR}/client-key.pem" \
        -out "${CERTS_DIR}/client.csr" \
        -config "${CERTS_DIR}/client-san.cnf"
    
    # Sign with Root CA
    openssl x509 -req \
        -in "${CERTS_DIR}/client.csr" \
        -CA "${CERTS_DIR}/root-ca.pem" \
        -CAkey "${CERTS_DIR}/root-ca-key.pem" \
        -CAcreateserial \
        -out "${CERTS_DIR}/client-cert.pem" \
        -days ${VALIDITY_DAYS} \
        -sha256 \
        -extensions req_ext \
        -extfile "${CERTS_DIR}/client-san.cnf"
    
    # Create PKCS12 keystore for client
    openssl pkcs12 -export \
        -in "${CERTS_DIR}/client-cert.pem" \
        -inkey "${CERTS_DIR}/client-key.pem" \
        -out "${CERTS_DIR}/client-keystore.p12" \
        -name "client" \
        -CAfile "${CERTS_DIR}/root-ca.pem" \
        -caname "root" \
        -password "pass:${PASSWORD}"
    
    log_info "Client certificate generated successfully"
}

# Generate Truststores
generate_truststores() {
    log_info "Generating truststores..."
    
    # Create middleware truststore (contains Root CA to verify client certs)
    keytool -importcert \
        -alias root-ca \
        -file "${CERTS_DIR}/root-ca.pem" \
        -keystore "${CERTS_DIR}/middleware-truststore.p12" \
        -storetype PKCS12 \
        -storepass "${PASSWORD}" \
        -noprompt
    
    # Create client truststore (contains Root CA to verify server cert)
    keytool -importcert \
        -alias root-ca \
        -file "${CERTS_DIR}/root-ca.pem" \
        -keystore "${CERTS_DIR}/client-truststore.p12" \
        -storetype PKCS12 \
        -storepass "${PASSWORD}" \
        -noprompt
    
    log_info "Truststores generated successfully"
}

# Display certificate info
display_cert_info() {
    log_info "Certificate Information:"
    echo ""
    echo "=== Root CA ==="
    openssl x509 -in "${CERTS_DIR}/root-ca.pem" -noout -subject -serial
    echo ""
    echo "=== Middleware Server Certificate ==="
    openssl x509 -in "${CERTS_DIR}/middleware-cert.pem" -noout -subject -serial
    echo ""
    echo "=== Client Certificate ==="
    openssl x509 -in "${CERTS_DIR}/client-cert.pem" -noout -subject -serial
    echo ""
}

# Main execution
main() {
    log_info "Starting certificate generation..."
    log_info "Output directory: ${CERTS_DIR}"
    
    cleanup
    generate_root_ca
    generate_middleware_cert
    generate_client_cert
    generate_truststores
    display_cert_info
    
    # Cleanup temporary files
    rm -f "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.srl "${CERTS_DIR}"/*.cnf 2>/dev/null || true
    
    log_info "Certificate generation completed!"
    log_info ""
    log_info "Generated files:"
    log_info "  - root-ca.pem            : Root CA certificate"
    log_info "  - root-ca-key.pem        : Root CA private key"
    log_info "  - middleware-keystore.p12: Middleware server keystore"
    log_info "  - middleware-truststore.p12: Middleware truststore (for client verification)"
    log_info "  - client-keystore.p12    : Client (user-bff) keystore"
    log_info "  - client-truststore.p12  : Client truststore (for server verification)"
    log_info ""
    log_info "Keystore password: ${PASSWORD}"
}

main "$@"
