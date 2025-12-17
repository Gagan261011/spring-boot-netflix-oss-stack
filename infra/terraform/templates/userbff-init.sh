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

# Get instance metadata
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
HOSTNAME=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)

echo "Instance Info: Private=$PRIVATE_IP, Public=$PUBLIC_IP, Hostname=$HOSTNAME"
echo "Middleware Host: $MIDDLEWARE_HOST"

# System update and dependencies
echo "[1/11] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "[2/11] Installing Java 17, Maven, Git, OpenSSL..."
apt-get install -y openjdk-17-jdk maven git curl jq openssl

echo "[3/11] Creating service user and directories..."
useradd -r -s /bin/false $SERVICE_NAME || true
mkdir -p /opt/$SERVICE_NAME/certs
mkdir -p /var/log/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /var/log/$SERVICE_NAME

echo "[4/11] Waiting for mTLS Middleware to be available..."
for i in {1..150}; do
    # Check if middleware's cert server is available on port 9999
    if curl -s http://$MIDDLEWARE_HOST:9999/ 2>/dev/null | grep -q "client-keystore.p12"; then
        echo "mTLS Middleware cert server is available!"
        break
    fi
    echo "Waiting for mTLS Middleware cert server at $MIDDLEWARE_HOST:9999... ($i/150)"
    sleep 10
done

echo "[5/11] Fetching client certificates from middleware..."
CERTS_DIR="/opt/$SERVICE_NAME/certs"
cd $CERTS_DIR

# Fetch certificates from middleware's cert server on port 9999
MAX_RETRIES=30
RETRY_DELAY=10
CERTS_FETCHED=false

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempting to fetch certificates (attempt $i of $MAX_RETRIES)..."
    
    # Fetch from middleware's cert server on port 9999
    if curl -sf "http://$MIDDLEWARE_HOST:9999/root-ca.pem" -o root-ca.pem 2>/dev/null && \
       curl -sf "http://$MIDDLEWARE_HOST:9999/client-keystore.p12" -o client-keystore.p12 2>/dev/null && \
       curl -sf "http://$MIDDLEWARE_HOST:9999/client-truststore.p12" -o client-truststore.p12 2>/dev/null; then
        echo "Certificates fetched from middleware successfully!"
        CERTS_FETCHED=true
        break
    fi
    
    echo "Cert fetch failed, retrying in $RETRY_DELAY seconds..."
    sleep $RETRY_DELAY
done

if [ "$CERTS_FETCHED" != "true" ]; then
    echo "ERROR: Failed to fetch certificates from middleware after $MAX_RETRIES attempts!"
    echo "Checking middleware cert server status..."
    curl -v http://$MIDDLEWARE_HOST:9999/ 2>&1 || true
    exit 1
fi

# Set permissions
chmod 644 $CERTS_DIR/*.pem 2>/dev/null || true
chmod 644 $CERTS_DIR/*.p12
chown -R $SERVICE_NAME:$SERVICE_NAME $CERTS_DIR

echo "Client certificates:"
ls -la $CERTS_DIR

echo "[6/11] Cloning repository (with retries)..."
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

echo "[7/11] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/user-bff -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

cp /opt/$SERVICE_NAME/repo/services/user-bff/target/user-bff.jar /opt/$SERVICE_NAME/app.jar
chown $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME/app.jar

echo "[8/11] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=User BFF Service
After=network.target

[Service]
Type=simple
User=$SERVICE_NAME
Group=$SERVICE_NAME
Environment="JAVA_OPTS=$JAVA_OPTS"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar \
    --spring.config.import=optional:configserver:http://$CONFIG_HOST:8888 \
    --eureka.client.service-url.defaultZone=http://$EUREKA_HOST:8761/eureka \
    --middleware.url=https://$MIDDLEWARE_HOST:8443 \
    --mtls.keystore=file:/opt/$SERVICE_NAME/certs/client-keystore.p12 \
    --mtls.keystore-password=$PASSWORD \
    --mtls.truststore=file:/opt/$SERVICE_NAME/certs/client-truststore.p12 \
    --mtls.truststore-password=$PASSWORD
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
# User-BFF uses port 8081 from config-repo
ACTUAL_PORT=8081
for i in {1..90}; do
    if curl -s http://localhost:$ACTUAL_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP on port $ACTUAL_PORT!"
        break
    fi
    echo "Waiting for $SERVICE_NAME on port $ACTUAL_PORT... ($i/90)"
    sleep 5
done

echo "[11/11] Testing REST endpoint..."
sleep 10
curl -s -X POST http://localhost:8081/api/rest/echo \
    -H "Content-Type: application/json" \
    -d '{"type":"test","message":"hello","amount":100}' || echo "REST endpoint test pending..."

echo "=========================================="
echo "User BFF provisioning complete!"
echo "Service URL: http://$PRIVATE_IP:8081"
echo "REST: http://$PRIVATE_IP:8081/api/rest/echo"
echo "SOAP: http://$PRIVATE_IP:8081/ws"
echo "GraphQL: http://$PRIVATE_IP:8081/graphql"
echo "=========================================="
