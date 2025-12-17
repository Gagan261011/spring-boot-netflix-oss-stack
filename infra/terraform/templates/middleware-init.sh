#!/bin/bash
#
# mTLS Middleware Initialization Script
# Generates certs with dynamic IPs and starts middleware service
#

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting mTLS Middleware provisioning..."
echo "Timestamp: $(date)"
echo "=========================================="

# Variables from Terraform
GIT_REPO_URL="${git_repo_url}"
GIT_BRANCH="${git_branch}"
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
CONFIG_HOST="${config_host}"
EUREKA_HOST="${eureka_host}"
BACKEND_HOST="${backend_host}"
JAVA_OPTS="${java_opts}"
PASSWORD="changeit"

# Get instance metadata - CRITICAL for dynamic IPs
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "127.0.0.1")
HOSTNAME=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)

echo "Instance Info: Private=$PRIVATE_IP, Public=$PUBLIC_IP, Hostname=$HOSTNAME"

# System update and dependencies
echo "[1/11] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "[2/11] Installing Java 17, Maven, Git, and OpenSSL..."
apt-get install -y openjdk-17-jdk maven git curl jq openssl

echo "[3/11] Creating service user and directories..."
useradd -r -s /bin/false $SERVICE_NAME || true
mkdir -p /opt/$SERVICE_NAME/certs
mkdir -p /var/log/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /var/log/$SERVICE_NAME

echo "[4/11] Waiting for Core Backend to be available..."
for i in {1..120}; do
    if curl -s http://$BACKEND_HOST:8082/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "Core Backend is available!"
        break
    fi
    echo "Waiting for Core Backend at $BACKEND_HOST:8082... ($i/120)"
    sleep 10
done

echo "[5/11] Cloning repository (with retries)..."
cd /opt/$SERVICE_NAME
MAX_RETRIES=10
RETRY_DELAY=30
for i in $(seq 1 $MAX_RETRIES); do
    echo "Git clone attempt $i of $MAX_RETRIES..."
    if git clone --branch $GIT_BRANCH $GIT_REPO_URL repo; then
        echo "Git clone successful!"
        break
    else
        echo "Git clone failed, waiting $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        if [ $i -eq $MAX_RETRIES ]; then
            echo "ERROR: Git clone failed after $MAX_RETRIES attempts!"
            exit 1
        fi
    fi
done

echo "[6/11] Generating mTLS certificates with dynamic IPs..."
CERTS_DIR="/opt/$SERVICE_NAME/certs"
cd $CERTS_DIR

# Generate Root CA
openssl genrsa -out root-ca-key.pem 4096
openssl req -x509 -new -nodes -key root-ca-key.pem -sha256 -days 3650 -out root-ca.pem \
    -subj "/C=US/ST=California/L=SF/O=Netflix/OU=DevOps/CN=RootCA"

# Generate Middleware Server Cert with DYNAMIC IPs
cat > middleware-san.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext
x509_extensions = v3_ext
[dn]
C = US
ST = California
L = SF
O = Netflix
OU = Middleware
CN = mtls-middleware
[req_ext]
subjectAltName = @alt_names
[v3_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = mtls-middleware
DNS.2 = localhost
DNS.3 = $HOSTNAME
DNS.4 = *.compute.amazonaws.com
DNS.5 = *.ec2.internal
IP.1 = 127.0.0.1
IP.2 = $PRIVATE_IP
IP.3 = $PUBLIC_IP
EOF

echo "Middleware SAN config:"
cat middleware-san.cnf

openssl genrsa -out middleware-key.pem 2048
openssl req -new -key middleware-key.pem -out middleware.csr -config middleware-san.cnf
openssl x509 -req -in middleware.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
    -out middleware-cert.pem -days 3650 -sha256 -extensions v3_ext -extfile middleware-san.cnf

echo "Middleware certificate SANs:"
openssl x509 -in middleware-cert.pem -noout -text | grep -A1 "Subject Alternative Name"

# Create Middleware Keystore
openssl pkcs12 -export -in middleware-cert.pem -inkey middleware-key.pem \
    -out middleware-keystore.p12 -name "middleware" -CAfile root-ca.pem \
    -caname "root" -password "pass:$PASSWORD"

# Create Middleware Truststore (for client cert verification)
keytool -importcert -alias root-ca -file root-ca.pem -keystore middleware-truststore.p12 \
    -storetype PKCS12 -storepass "$PASSWORD" -noprompt

# Generate Client Cert (for user-bff) - signed by SAME CA
cat > client-san.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext
x509_extensions = v3_ext
[dn]
C = US
O = Netflix
CN = user-bff
[req_ext]
subjectAltName = @alt_names
[v3_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = user-bff
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client.csr -config client-san.cnf
openssl x509 -req -in client.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
    -out client-cert.pem -days 3650 -sha256 -extensions v3_ext -extfile client-san.cnf

# Create Client Keystore
openssl pkcs12 -export -in client-cert.pem -inkey client-key.pem \
    -out client-keystore.p12 -name "client" -CAfile root-ca.pem \
    -caname "root" -password "pass:$PASSWORD"

# Create Client Truststore
keytool -importcert -alias root-ca -file root-ca.pem -keystore client-truststore.p12 \
    -storetype PKCS12 -storepass "$PASSWORD" -noprompt

# Cleanup temp files
rm -f *.csr *.srl *.cnf

# Set permissions
chmod 644 $CERTS_DIR/*.pem
chmod 644 $CERTS_DIR/*.p12
chown -R $SERVICE_NAME:$SERVICE_NAME $CERTS_DIR

echo "Certificates generated:"
ls -la $CERTS_DIR

echo "[7/11] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/mtls-middleware -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

cp /opt/$SERVICE_NAME/repo/services/mtls-middleware/target/mtls-middleware.jar /opt/$SERVICE_NAME/app.jar
chown $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME/app.jar

echo "[8/11] Setting up certificate HTTP server for user-bff..."
# Start a simple Python HTTP server to serve certs to user-bff
cat > /opt/$SERVICE_NAME/certs/serve_certs.py << 'PYEOF'
#!/usr/bin/env python3
import http.server
import socketserver
import os

PORT = 9999
DIRECTORY = "/opt/mtls-middleware/certs"

class CORSRequestHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()

os.chdir(DIRECTORY)
with socketserver.TCPServer(("", PORT), CORSRequestHandler) as httpd:
    print(f"Serving certs on port {PORT}")
    httpd.serve_forever()
PYEOF
chmod +x /opt/$SERVICE_NAME/certs/serve_certs.py

# Create systemd service for cert server
cat > /etc/systemd/system/cert-server.service << EOF
[Unit]
Description=Certificate HTTP Server for mTLS
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/$SERVICE_NAME/certs/serve_certs.py
WorkingDirectory=/opt/$SERVICE_NAME/certs
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cert-server
systemctl start cert-server
echo "Certificate server started on port 9999"

echo "[9/11] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=mTLS Middleware Service
After=network.target

[Service]
Type=simple
User=$SERVICE_NAME
Group=$SERVICE_NAME
Environment="JAVA_OPTS=$JAVA_OPTS"
Environment="KEYSTORE_PATH=/opt/$SERVICE_NAME/certs/middleware-keystore.p12"
Environment="KEYSTORE_PASSWORD=$PASSWORD"
Environment="TRUSTSTORE_PATH=/opt/$SERVICE_NAME/certs/middleware-truststore.p12"
Environment="TRUSTSTORE_PASSWORD=$PASSWORD"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar \
    --spring.config.import=optional:configserver:http://$CONFIG_HOST:8888 \
    --eureka.client.service-url.defaultZone=http://$EUREKA_HOST:8761/eureka \
    --backend.url=http://$BACKEND_HOST:8082 \
    --server.ssl.key-store=file:/opt/$SERVICE_NAME/certs/middleware-keystore.p12 \
    --server.ssl.key-store-password=$PASSWORD \
    --server.ssl.key-store-type=PKCS12 \
    --server.ssl.key-alias=middleware \
    --server.ssl.trust-store=file:/opt/$SERVICE_NAME/certs/middleware-truststore.p12 \
    --server.ssl.trust-store-password=$PASSWORD \
    --server.ssl.trust-store-type=PKCS12 \
    --server.ssl.client-auth=need
WorkingDirectory=/opt/$SERVICE_NAME
Restart=always
RestartSec=10
StandardOutput=append:/var/log/$SERVICE_NAME/$SERVICE_NAME.log
StandardError=append:/var/log/$SERVICE_NAME/$SERVICE_NAME-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "[10/11] Starting service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "[11/12] Waiting for service to be healthy..."
for i in {1..90}; do
    # Check management port (HTTP) - middleware uses port 8443 for HTTPS, but may have separate management port
    if curl -s http://localhost:8080/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP!"
        break
    fi
    # Also try the HTTPS port with -k to skip cert verification
    if curl -sk https://localhost:$SERVICE_PORT/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME HTTPS is UP!"
        break
    fi
    echo "Waiting... ($i/90)"
    sleep 5
done

echo "[12/12] Testing HTTPS endpoint..."
sleep 5
curl -sk https://localhost:$SERVICE_PORT/actuator/health || echo "HTTPS requires client cert (expected)"

echo "=========================================="
echo "mTLS Middleware provisioning complete!"
echo "HTTPS Port: $SERVICE_PORT (requires client cert)"
echo "Cert Server Port: 9999 (HTTP)"
echo "Private IP: $PRIVATE_IP"
echo ""
echo "Client certs for user-bff available at:"
echo "  - http://$PRIVATE_IP:9999/client-keystore.p12"
echo "  - http://$PRIVATE_IP:9999/client-truststore.p12"
echo "  - http://$PRIVATE_IP:9999/root-ca.pem"
echo "=========================================="
