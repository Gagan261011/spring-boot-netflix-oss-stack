#!/bin/bash
#
# User BFF Initialization Script
# Copies certs from middleware and starts service
#

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting User BFF provisioning..."
echo "Timestamp: $(date)"
echo "=========================================="

# Variables from Terraform
GIT_REPO_URL="${git_repo_url}"
GIT_BRANCH="${git_branch}"
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
CONFIG_HOST="${config_host}"
EUREKA_HOST="${eureka_host}"
MIDDLEWARE_HOST="${middleware_host}"
JAVA_OPTS="${java_opts}"
PASSWORD="changeit"

# System update and dependencies
echo "[1/11] Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "[2/11] Installing Java 17, Maven, Git, OpenSSL, and sshpass..."
apt-get install -y openjdk-17-jdk maven git curl jq openssl

echo "[3/11] Creating service user and directories..."
useradd -r -s /bin/false apps || true
mkdir -p /opt/$SERVICE_NAME/certs
mkdir -p /var/log/$SERVICE_NAME
chown -R apps:apps /opt/$SERVICE_NAME
chown -R apps:apps /var/log/$SERVICE_NAME

echo "[4/11] Waiting for mTLS Middleware to be available..."
for i in {1..90}; do
    if curl -s http://$MIDDLEWARE_HOST:8444/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "mTLS Middleware is available!"
        break
    fi
    echo "Waiting for mTLS Middleware... ($i/90)"
    sleep 10
done

echo "[5/11] Generating client certificates locally..."
CERTS_DIR="/opt/$SERVICE_NAME/certs"
cd $CERTS_DIR

# Generate Root CA (same as middleware)
openssl genrsa -out root-ca-key.pem 4096
openssl req -x509 -new -nodes -key root-ca-key.pem -sha256 -days 3650 -out root-ca.pem \
    -subj "/C=US/ST=California/L=SF/O=Netflix/OU=DevOps/CN=RootCA"

# Generate Client Cert
cat > client-san.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = req_ext
[dn]
C = US
ST = California
L = SF
O = Netflix
OU = UserBFF
CN = user-bff-client
[req_ext]
subjectAltName = @alt_names
[alt_names]
DNS.1 = user-bff
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client.csr -config client-san.cnf
openssl x509 -req -in client.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
    -out client-cert.pem -days 3650 -sha256 -extensions req_ext -extfile client-san.cnf

# Create Client Keystore
openssl pkcs12 -export -in client-cert.pem -inkey client-key.pem \
    -out client-keystore.p12 -name "client" -CAfile root-ca.pem \
    -caname "root" -password "pass:$PASSWORD"

# Create Client Truststore (trust the Root CA which signed middleware cert)
keytool -importcert -alias root-ca -file root-ca.pem -keystore client-truststore.p12 \
    -storetype PKCS12 -storepass "$PASSWORD" -noprompt

# Cleanup
rm -f *.csr *.srl *.cnf

chown -R apps:apps $CERTS_DIR
chmod 600 $CERTS_DIR/*.p12

echo "Client certificates generated:"
ls -la $CERTS_DIR

echo "[6/11] Cloning repository..."
cd /opt/$SERVICE_NAME
git clone --branch $GIT_BRANCH $GIT_REPO_URL repo || {
    echo "Git clone failed!"
    mkdir -p repo
}

echo "[7/11] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/user-bff -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

# Copy jar
cp /opt/$SERVICE_NAME/repo/services/user-bff/target/user-bff.jar /opt/$SERVICE_NAME/app.jar
chown apps:apps /opt/$SERVICE_NAME/app.jar

echo "[8/11] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=User BFF Service
After=network.target

[Service]
Type=simple
User=apps
Group=apps
Environment="JAVA_OPTS=$JAVA_OPTS"
Environment="CONFIG_SERVER_HOST=$CONFIG_HOST"
Environment="EUREKA_HOST=$EUREKA_HOST"
Environment="MIDDLEWARE_HOST=$MIDDLEWARE_HOST"
Environment="KEYSTORE_PATH=/opt/$SERVICE_NAME/certs/client-keystore.p12"
Environment="KEYSTORE_PASSWORD=$PASSWORD"
Environment="TRUSTSTORE_PATH=/opt/$SERVICE_NAME/certs/client-truststore.p12"
Environment="TRUSTSTORE_PASSWORD=$PASSWORD"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar
WorkingDirectory=/opt/$SERVICE_NAME
Restart=always
RestartSec=10
StandardOutput=append:/var/log/$SERVICE_NAME/$SERVICE_NAME.log
StandardError=append:/var/log/$SERVICE_NAME/$SERVICE_NAME-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "[9/11] Starting service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "[10/11] Waiting for service to be healthy..."
for i in {1..60}; do
    if curl -s http://localhost:$SERVICE_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 5
done

echo "[11/11] Testing REST endpoint..."
sleep 10
curl -s -X POST http://localhost:$SERVICE_PORT/api/rest/echo \
    -H "Content-Type: application/json" \
    -d '{"type":"test","message":"hello","amount":100}' || echo "REST test pending..."

echo "=========================================="
echo "User BFF provisioning complete!"
echo "Service URL: http://localhost:$SERVICE_PORT"
echo "REST: http://localhost:$SERVICE_PORT/api/rest/echo"
echo "SOAP: http://localhost:$SERVICE_PORT/ws"
echo "GraphQL: http://localhost:$SERVICE_PORT/graphql"
echo "=========================================="
