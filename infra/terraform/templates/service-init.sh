#!/bin/bash
#
# Generic Service Initialization Script (Core Backend)
#

set -e
exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "Starting ${service_name} provisioning..."
echo "Timestamp: $(date)"
echo "=========================================="

# Variables from Terraform
GIT_REPO_URL="${git_repo_url}"
GIT_BRANCH="${git_branch}"
SERVICE_NAME="${service_name}"
SERVICE_PORT="${service_port}"
CONFIG_HOST="${config_host}"
EUREKA_HOST="${eureka_host}"
JAVA_OPTS="${java_opts}"

# Get instance metadata
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PRIVATE_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)
PUBLIC_IP=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
HOSTNAME=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-hostname)

echo "Instance Info: Private=$PRIVATE_IP, Public=$PUBLIC_IP, Hostname=$HOSTNAME"

# System update and dependencies
echo "[1/9] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

echo "[2/9] Installing Java 17, Maven, and Git..."
apt-get install -y openjdk-17-jdk maven git curl jq

echo "[3/9] Creating service user and directories..."
useradd -r -s /bin/false $SERVICE_NAME || true
mkdir -p /opt/$SERVICE_NAME
mkdir -p /var/log/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME
chown -R $SERVICE_NAME:$SERVICE_NAME /var/log/$SERVICE_NAME

echo "[4/9] Waiting for Eureka Server..."
for i in {1..90}; do
    if curl -s http://$EUREKA_HOST:8761/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
        echo "Eureka Server is available!"
        break
    fi
    echo "Waiting for Eureka Server at $EUREKA_HOST:8761... ($i/90)"
    sleep 10
done

echo "[5/9] Cloning repository (with retries)..."
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

echo "[6/9] Building service..."
cd /opt/$SERVICE_NAME/repo
mvn -pl services/$SERVICE_NAME -am clean package -DskipTests -q || {
    echo "Build failed!"
    exit 1
}

cp /opt/$SERVICE_NAME/repo/services/$SERVICE_NAME/target/$SERVICE_NAME.jar /opt/$SERVICE_NAME/app.jar
chown $SERVICE_NAME:$SERVICE_NAME /opt/$SERVICE_NAME/app.jar

echo "[7/9] Creating systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=$SERVICE_NAME Service
After=network.target

[Service]
Type=simple
User=$SERVICE_NAME
Group=$SERVICE_NAME
Environment="JAVA_OPTS=$JAVA_OPTS"
ExecStart=/usr/bin/java \$JAVA_OPTS -jar /opt/$SERVICE_NAME/app.jar --spring.config.import=optional:configserver:http://$CONFIG_HOST:8888 --eureka.client.service-url.defaultZone=http://$EUREKA_HOST:8761/eureka
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
# Core-backend uses port 8082 from config-repo, not the terraform port variable
ACTUAL_PORT=8082
for i in {1..90}; do
    if curl -s http://localhost:$ACTUAL_PORT/actuator/health | grep -q '"status":"UP"'; then
        echo "$SERVICE_NAME is UP on port $ACTUAL_PORT!"
        break
    fi
    echo "Waiting for $SERVICE_NAME on port $ACTUAL_PORT... ($i/90)"
    sleep 5
done

echo "=========================================="
echo "$SERVICE_NAME provisioning complete!"
echo "Service URL: http://$PRIVATE_IP:8082"
echo "=========================================="
