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

# Get instance metadata
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
HOSTNAME=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)

echo "Instance Info: Private=$PRIVATE_IP, Public=$PUBLIC_IP, Hostname=$HOSTNAME"

# System update and dependencies
echo "[1/8] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "[2/8] Installing Java 17, Maven, and Git..."
apt-get install -y openjdk-17-jdk maven git curl jq

# Verify installations
java -version
mvn -version
git --version

echo "[3/8] Creating service user and directories..."
useradd -r -s /bin/false $SERVICE_NAME || true
mkdir -p /opt/$SERVICE_NAME/config-repo
mkdir -p /var/log/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /var/log/$SERVICE_NAME

echo "[4/8] Cloning repository (with retries)..."
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

echo "[5/8] Copying config-repo..."
if [ -d "/opt/$SERVICE_NAME/repo/config-repo" ]; then
    cp -r /opt/$SERVICE_NAME/repo/config-repo/* /opt/$SERVICE_NAME/config-repo/
    echo "Config repo copied successfully"
else
    echo "ERROR: Config repo not found in repository!"
    exit 1
fi

echo "[6/8] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/config-server -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

# Copy jar
cp /opt/$SERVICE_NAME/repo/services/config-server/target/config-server.jar /opt/$SERVICE_NAME/app.jar
chown $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME/app.jar

echo "[7/8] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Config Server
After=network.target

[Service]
Type=simple
User=$SERVICE_NAME
Group=$SERVICE_NAME
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
for i in {1..90}; do
    if curl -s http://localhost:$SERVICE_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "Config Server is UP!"
        break
    fi
    echo "Waiting for Config Server on port $SERVICE_PORT... ($i/90)"
    sleep 5
done

echo "=========================================="
echo "Config Server provisioning complete!"
echo "Service URL: http://$PRIVATE_IP:$SERVICE_PORT"
echo "=========================================="
