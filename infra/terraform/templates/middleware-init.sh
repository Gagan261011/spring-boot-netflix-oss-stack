#!/bin/bash
#
# mTLS Middleware Initialization Script
# Generates certs and starts middleware service
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

# System update and dependencies
echo "[1/11] Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "[2/11] Installing Java 17, Maven, Git, and OpenSSL..."
apt-get install -y openjdk-17-jdk maven git curl jq openssl

echo "[3/11] Creating service user and directories..."
useradd -r -s /bin/false apps || true
mkdir -p /opt/$SERVICE_NAME/certs
mkdir -p /var/log/$SERVICE_NAME
chown -R apps:apps /opt/$SERVICE_NAME
chown -R apps:apps /var/log/$SERVICE_NAME

echo "[4/11] Waiting for Core Backend to be available..."
for i in {1..90}; do
    if curl -s http://$BACKEND_HOST:8082/actuator/health | grep -q '"status":"UP"'; then
        echo "Core Backend is available!"
        break
    fi
    echo "Waiting for Core Backend... ($i/90)"
    sleep 10
done

echo "[5/11] Cloning repository..."
cd /opt/$SERVICE_NAME
git clone --branch $GIT_BRANCH $GIT_REPO_URL repo || {
    echo "Git clone failed!"
    mkdir -p repo
}

echo "[6/11] Generating mTLS certificates..."
CERTS_DIR="/opt/$SERVICE_NAME/certs"
cd $CERTS_DIR

# Generate Root CA
openssl genrsa -out root-ca-key.pem 4096
openssl req -x509 -new -nodes -key root-ca-key.pem -sha256 -days 3650 -out root-ca.pem \
    -subj "/C=US/ST=California/L=SF/O=Netflix/OU=DevOps/CN=RootCA"

# Generate Middleware Server Cert
cat > middleware-san.cnf << EOF
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

openssl genrsa -out middleware-key.pem 2048
openssl req -new -key middleware-key.pem -out middleware.csr -config middleware-san.cnf
openssl x509 -req -in middleware.csr -CA root-ca.pem -CAkey root-ca-key.pem -CAcreateserial \
    -out middleware-cert.pem -days 3650 -sha256 -extensions req_ext -extfile middleware-san.cnf

# Create Middleware Keystore
openssl pkcs12 -export -in middleware-cert.pem -inkey middleware-key.pem \
    -out middleware-keystore.p12 -name "middleware" -CAfile root-ca.pem \
    -caname "root" -password "pass:$PASSWORD"

# Create Middleware Truststore (for client cert verification)
keytool -importcert -alias root-ca -file root-ca.pem -keystore middleware-truststore.p12 \
    -storetype PKCS12 -storepass "$PASSWORD" -noprompt

# Generate Client Cert (for user-bff)
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

# Create Client Truststore
keytool -importcert -alias root-ca -file root-ca.pem -keystore client-truststore.p12 \
    -storetype PKCS12 -storepass "$PASSWORD" -noprompt

# Cleanup
rm -f *.csr *.srl *.cnf

chown -R apps:apps $CERTS_DIR
chmod 600 $CERTS_DIR/*.p12

echo "Certificates generated:"
ls -la $CERTS_DIR

echo "[7/11] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/mtls-middleware -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

# Copy jar
cp /opt/$SERVICE_NAME/repo/services/mtls-middleware/target/mtls-middleware.jar /opt/$SERVICE_NAME/app.jar
chown apps:apps /opt/$SERVICE_NAME/app.jar

echo "[8/11] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=mTLS Middleware Service
After=network.target

[Service]
Type=simple
User=apps
Group=apps
Environment="JAVA_OPTS=$JAVA_OPTS"
Environment="CONFIG_SERVER_HOST=$CONFIG_HOST"
Environment="EUREKA_HOST=$EUREKA_HOST"
Environment="BACKEND_HOST=$BACKEND_HOST"
Environment="KEYSTORE_PATH=/opt/$SERVICE_NAME/certs/middleware-keystore.p12"
Environment="KEYSTORE_PASSWORD=$PASSWORD"
Environment="TRUSTSTORE_PATH=/opt/$SERVICE_NAME/certs/middleware-truststore.p12"
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
    if curl -sk https://localhost:$SERVICE_PORT/middleware/health 2>/dev/null | grep -q "healthy"; then
        echo "$SERVICE_NAME is UP!"
        break
    fi
    # Try management port as fallback
    if curl -s http://localhost:8444/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP (via management port)!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 5
done

echo "[11/11] Outputting cert info for other services..."
echo "Client certificates are at: /opt/$SERVICE_NAME/certs/"
echo "Copy client-keystore.p12 and client-truststore.p12 to user-bff"

echo "=========================================="
echo "mTLS Middleware provisioning complete!"
echo "Service URL: https://localhost:$SERVICE_PORT"
echo "Management URL: http://localhost:8444/actuator/health"
echo "=========================================="
