#!/bin/bash
#
# Config Server Initialization Script
# This runs on first boot via cloud-init
#

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting Config Server provisioning..."
echo "Timestamp: $(date)"
echo "=========================================="

# Variables from Terraform
GIT_REPO_URL="${git_repo_url}"
GIT_BRANCH="${git_branch}"
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
JAVA_OPTS="${java_opts}"

# System update and dependencies
echo "[1/8] Updating system packages..."
apt-get update -y
apt-get upgrade -y

echo "[2/8] Installing Java 17, Maven, and Git..."
apt-get install -y openjdk-17-jdk maven git curl jq

# Verify installations
java -version
mvn -version
git --version

echo "[3/8] Creating service user and directories..."
useradd -r -s /bin/false apps || true
mkdir -p /opt/$SERVICE_NAME/config-repo
mkdir -p /var/log/$SERVICE_NAME
chown -R apps:apps /opt/$SERVICE_NAME
chown -R apps:apps /var/log/$SERVICE_NAME

echo "[4/8] Cloning repository..."
cd /opt/$SERVICE_NAME
git clone --branch $GIT_BRANCH $GIT_REPO_URL repo || {
    echo "Git clone failed, creating local structure..."
    mkdir -p repo
}

echo "[5/8] Copying config-repo..."
if [ -d "/opt/$SERVICE_NAME/repo/config-repo" ]; then
    cp -r /opt/$SERVICE_NAME/repo/config-repo/* /opt/$SERVICE_NAME/config-repo/
else
    echo "Config repo not found, creating default configs..."
    cat > /opt/$SERVICE_NAME/config-repo/application.yml << 'CONFIGEOF'
spring:
  profiles:
    active: aws
CONFIGEOF
fi

echo "[6/8] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/config-server -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

# Copy jar
cp /opt/$SERVICE_NAME/repo/services/config-server/target/config-server.jar /opt/$SERVICE_NAME/app.jar
chown apps:apps /opt/$SERVICE_NAME/app.jar

echo "[7/8] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Config Server
After=network.target

[Service]
Type=simple
User=apps
Group=apps
Environment="JAVA_OPTS=$JAVA_OPTS"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar --spring.cloud.config.server.native.search-locations=file:/opt/$SERVICE_NAME/config-repo
WorkingDirectory=/opt/$SERVICE_NAME
Restart=always
RestartSec=10
StandardOutput=append:/var/log/$SERVICE_NAME/$SERVICE_NAME.log
StandardError=append:/var/log/$SERVICE_NAME/$SERVICE_NAME-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "[8/8] Starting service..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl start $SERVICE_NAME

# Wait for service to be healthy
echo "Waiting for Config Server to be healthy..."
for i in {1..60}; do
    if curl -s http://localhost:$SERVICE_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "Config Server is UP!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 5
done

echo "=========================================="
echo "Config Server provisioning complete!"
echo "Service URL: http://localhost:$SERVICE_PORT"
echo "=========================================="
