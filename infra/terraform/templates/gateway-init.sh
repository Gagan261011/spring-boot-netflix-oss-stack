#!/bin/bash
#
# Cloud Gateway Initialization Script
# Final service in the chain
#

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting Cloud Gateway provisioning..."
echo "Timestamp: $(date)"
echo "=========================================="

# Variables from Terraform
GIT_REPO_URL="${git_repo_url}"
GIT_BRANCH="${git_branch}"
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
CONFIG_HOST="${config_host}"
EUREKA_HOST="${eureka_host}"
USERBFF_HOST="${userbff_host}"
JAVA_OPTS="${java_opts}"

# System update and dependencies
echo "[1/9] Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "[2/9] Installing Java 17, Maven, and Git..."
apt-get install -y openjdk-17-jdk maven git curl jq

echo "[3/9] Creating service user and directories..."
useradd -r -s /bin/false apps || true
mkdir -p /opt/$SERVICE_NAME
mkdir -p /var/log/$SERVICE_NAME
chown -R apps:apps /opt/$SERVICE_NAME
chown -R apps:apps /var/log/$SERVICE_NAME

echo "[4/9] Waiting for User BFF to be available..."
for i in {1..90}; do
    if curl -s http://$USERBFF_HOST:8081/actuator/health | grep -q '"status":"UP"'; then
        echo "User BFF is available!"
        break
    fi
    echo "Waiting for User BFF... ($i/90)"
    sleep 10
done

echo "[5/9] Cloning repository..."
cd /opt/$SERVICE_NAME
git clone --branch $GIT_BRANCH $GIT_REPO_URL repo || {
    echo "Git clone failed!"
    mkdir -p repo
}

echo "[6/9] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/cloud-gateway -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

# Copy jar
cp /opt/$SERVICE_NAME/repo/services/cloud-gateway/target/cloud-gateway.jar /opt/$SERVICE_NAME/app.jar
chown apps:apps /opt/$SERVICE_NAME/app.jar

echo "[7/9] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Cloud Gateway Service
After=network.target

[Service]
Type=simple
User=apps
Group=apps
Environment="JAVA_OPTS=$JAVA_OPTS"
Environment="CONFIG_SERVER_HOST=$CONFIG_HOST"
Environment="EUREKA_HOST=$EUREKA_HOST"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar
WorkingDirectory=/opt/$SERVICE_NAME
Restart=always
RestartSec=10
StandardOutput=append:/var/log/$SERVICE_NAME/$SERVICE_NAME.log
StandardError=append:/var/log/$SERVICE_NAME/$SERVICE_NAME-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "[8/9] Starting service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

echo "[9/9] Waiting for service to be healthy..."
for i in {1..60}; do
    if curl -s http://localhost:$SERVICE_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 5
done

# Final health check
echo "Testing full chain via Gateway..."
sleep 15
curl -s -X POST http://localhost:$SERVICE_PORT/api/rest/echo \
    -H "Content-Type: application/json" \
    -d '{"type":"sanity","message":"gateway-test","amount":99}' || echo "Full chain test pending..."

echo "=========================================="
echo "Cloud Gateway provisioning complete!"
echo "Service URL: http://localhost:$SERVICE_PORT"
echo "=========================================="
echo ""
echo "All services deployed! Stack is ready."
echo "Gateway is publicly accessible on port 8080"
echo "=========================================="
