# Spring Boot Netflix OSS Microservices Stack

[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-3.2.1-brightgreen.svg)](https://spring.io/projects/spring-boot)
[![Java](https://img.shields.io/badge/Java-17-orange.svg)](https://openjdk.java.net/)
[![Terraform](https://img.shields.io/badge/Terraform-1.0+-blueviolet.svg)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EC2-orange.svg)](https://aws.amazon.com/ec2/)

A production-ready, end-to-end microservices architecture using **Spring Boot 3.x**, **Netflix OSS** (Eureka, Config Server), **Spring Cloud Gateway**, with **mTLS** security, deployed on **AWS EC2** using **Terraform**.

## 🏗 Architecture

```
                                    ┌─────────────────────────────────────────────────────────────────┐
                                    │                        AWS VPC                                   │
                                    │                                                                   │
   ┌─────────┐                      │   ┌──────────────┐      ┌──────────────┐                        │
   │ Client  │──────HTTP:8080──────────▶│   Gateway    │      │Config Server │◀────────────────────┐  │
   └─────────┘                      │   │   :8080      │      │    :8888     │                     │  │
                                    │   └──────┬───────┘      └──────────────┘                     │  │
                                    │          │                                                    │  │
                                    │          ▼                                                    │  │
                                    │   ┌──────────────┐      ┌──────────────┐                     │  │
                                    │   │   User BFF   │      │Eureka Server │◀────── Discovery ───┘  │
                                    │   │    :8081     │      │    :8761     │                        │
                                    │   └──────┬───────┘      └──────────────┘                        │
                                    │          │                                                       │
                                    │          │ mTLS (client cert)                                   │
                                    │          ▼                                                       │
                                    │   ┌──────────────┐                                              │
                                    │   │  Middleware  │────────────────┐                             │
                                    │   │ :8443 (HTTPS)│                │                             │
                                    │   └──────────────┘                ▼                             │
                                    │          ▲              ┌──────────────┐                        │
                                    │          │              │Core Backend  │                        │
                                    │   Truststore verifies   │    :8082     │                        │
                                    │   client certificate    └──────────────┘                        │
                                    │                                                                   │
                                    └─────────────────────────────────────────────────────────────────┘
```

## 📦 Services

| Service | Port | Description |
|---------|------|-------------|
| **Config Server** | 8888 | Centralized configuration management |
| **Eureka Server** | 8761 | Service discovery and registration |
| **Cloud Gateway** | 8080 | API Gateway - **only public entry point** |
| **User BFF** | 8081 | Backend for Frontend with REST, SOAP, GraphQL |
| **mTLS Middleware** | 8443 | HTTPS service with client certificate verification |
| **Core Backend** | 8082 | Core business logic service |

## 🔐 mTLS Security Flow

```
User BFF ──────────────────────────────▶ mTLS Middleware
         │                                      │
         │  1. TLS Handshake                   │
         │  2. Client presents certificate      │
         │  3. Middleware validates via         │
         │     truststore                       │
         │  4. Extracts Subject DN + Serial     │
         │  5. Forwards to Backend with         │
         │     X-Client-Subject, X-Client-Serial│
         │                                      │
         ◀──────────────────────────────────────
                Response includes cert info
                (proof of mTLS verification)
```

## 🚀 Quick Start

### Prerequisites

- AWS Account with EC2 permissions
- AWS CLI configured (`aws configure`)
- Terraform >= 1.0.0
- SSH Key Pair in AWS
- Git
- (For local tests) Java 17, Maven

### 1. Clone Repository

```bash
git clone https://github.com/your-org/spring-boot-netflix-oss-stack.git
cd spring-boot-netflix-oss-stack
```

### 2. Configure Terraform

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region    = "us-east-1"
admin_cidr    = "YOUR_IP/32"    # Your public IP for SSH
key_pair_name = "your-key-pair" # AWS key pair name
git_repo_url  = "https://github.com/your-org/spring-boot-netflix-oss-stack.git"
git_branch    = "main"
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy everything
terraform apply -auto-approve
```

This will:
1. ✅ Create 6 EC2 instances (t3.medium, Ubuntu 22.04)
2. ✅ Configure security groups (Gateway public, others internal)
3. ✅ Install Java 17, Maven, Git on each VM
4. ✅ Clone the repository on each VM
5. ✅ Build only the relevant service on each VM
6. ✅ Generate mTLS certificates
7. ✅ Configure and start systemd services
8. ✅ Wait for dependencies in correct order
9. ✅ Run sanity tests automatically
10. ✅ Generate HTML/JSON reports locally

### 4. Access the Stack

After deployment (~10-15 minutes), Terraform outputs:
```
gateway_public_url = "http://X.X.X.X:8080"
```

### 5. Destroy Infrastructure

```bash
terraform destroy -auto-approve
```

## 📡 API Endpoints

All APIs are accessed through the **Gateway** (port 8080).

### REST API

```bash
# POST /api/rest/echo
curl -X POST "http://GATEWAY_IP:8080/api/rest/echo" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "payment",
    "message": "Process transaction",
    "amount": 150.00
  }'
```

**Response:**
```json
{
  "backendResponse": {
    "requestId": "uuid",
    "originalType": "payment",
    "originalMessage": "Process transaction",
    "originalAmount": 150.0,
    "computedOutput": "Processed payment request...",
    "processedBy": "core-backend",
    "instanceInfo": "ip-10-0-1-x",
    "timestamp": "2024-01-15T10:30:00Z",
    "clientCertSubject": "CN=user-bff-client,OU=UserBFF,O=Netflix,L=SF,ST=California,C=US",
    "clientCertSerial": "ABC123DEF456"
  },
  "middlewareProcessed": true,
  "clientCertSubject": "CN=user-bff-client,OU=UserBFF,O=Netflix...",
  "clientCertSerial": "ABC123DEF456"
}
```

### SOAP API

```bash
# POST /ws
curl -X POST "http://GATEWAY_IP:8080/ws" \
  -H "Content-Type: text/xml" \
  -H "SOAPAction: ProcessRequest" \
  -d '<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" 
                  xmlns:soap="http://netflix.oss.stack/bff/soap">
   <soapenv:Header/>
   <soapenv:Body>
      <soap:ProcessRequestMessage>
         <soap:type>order</soap:type>
         <soap:message>Create new order</soap:message>
         <soap:amount>299.99</soap:amount>
      </soap:ProcessRequestMessage>
   </soapenv:Body>
</soapenv:Envelope>'
```

**WSDL:** `http://GATEWAY_IP:8080/ws/process.wsdl`

### GraphQL API

```bash
# POST /graphql
curl -X POST "http://GATEWAY_IP:8080/graphql" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { process(type: \"transfer\", message: \"Fund transfer\", amount: 500.00) { requestId computedOutput clientCertSubject clientCertSerial middlewareProcessed } }"
  }'
```

**GraphiQL UI:** `http://GATEWAY_IP:8080/graphiql`

**GraphQL Schema:**
```graphql
type Mutation {
  process(type: String!, message: String!, amount: Float!): ProcessedResponse
}

type ProcessedResponse {
  requestId: String
  originalType: String
  originalMessage: String
  originalAmount: Float
  computedOutput: String
  processedBy: String
  instanceInfo: String
  timestamp: String
  clientCertSubject: String
  clientCertSerial: String
  middlewareProcessed: Boolean
}
```

## 🧪 Sanity Tests

Sanity tests run automatically after `terraform apply`. To run manually:

### Bash (Linux/macOS/WSL)
```bash
cd scripts/sanity
chmod +x run_sanity.sh
./run_sanity.sh GATEWAY_IP
```

### PowerShell (Windows)
```powershell
cd scripts\sanity
.\run_sanity.ps1 -GatewayIP GATEWAY_IP
```

### Reports Location
- `reports/sanity-report.json` - JSON test results
- `reports/sanity-report.html` - HTML visual report

## 📁 Project Structure

```
spring-boot-netflix-oss-stack/
├── pom.xml                          # Parent POM
├── README.md                        # This file
│
├── services/
│   ├── config-server/               # Spring Cloud Config Server
│   ├── eureka-server/               # Netflix Eureka Discovery
│   ├── cloud-gateway/               # Spring Cloud Gateway
│   ├── user-bff/                    # BFF with REST/SOAP/GraphQL
│   ├── mtls-middleware/             # mTLS HTTPS Service
│   └── core-backend/                # Core Business Logic
│
├── config-repo/                     # Externalized configurations
│   ├── application.yml
│   ├── eureka-server.yml
│   ├── cloud-gateway.yml
│   ├── user-bff.yml
│   ├── mtls-middleware.yml
│   └── core-backend.yml
│
├── infra/terraform/
│   ├── main.tf                      # Provider configuration
│   ├── variables.tf                 # Input variables
│   ├── network.tf                   # VPC, Security Groups
│   ├── ec2.tf                       # EC2 instances
│   ├── outputs.tf                   # Output values
│   ├── sanity.tf                    # Sanity test runner
│   ├── terraform.tfvars.example     # Example variables
│   └── templates/                   # Cloud-init scripts
│       ├── config-server-init.sh
│       ├── eureka-server-init.sh
│       ├── service-init.sh
│       ├── middleware-init.sh
│       ├── userbff-init.sh
│       └── gateway-init.sh
│
├── scripts/
│   ├── certs/
│   │   └── generate-certs.sh        # Certificate generation
│   └── sanity/
│       ├── run_sanity.sh            # Bash sanity tests
│       └── run_sanity.ps1           # PowerShell sanity tests
│
└── reports/
    ├── sanity-report.json           # Generated after tests
    └── sanity-report.html           # Generated after tests
```

## 🔧 Local Development

### Build All Services
```bash
mvn clean package -DskipTests
```

### Run Locally (Docker Compose alternative)
Start services in order:
1. Config Server
2. Eureka Server
3. Core Backend
4. mTLS Middleware (after generating certs)
5. User BFF
6. Cloud Gateway

### Generate Certificates Locally
```bash
cd scripts/certs
chmod +x generate-certs.sh
./generate-certs.sh
```

## 🏷 Spring Profiles

- `local` - For local development
- `aws` - For AWS deployment (default)

## 📊 Monitoring Endpoints

All services expose Actuator endpoints:
- Health: `/actuator/health`
- Info: `/actuator/info`

Gateway specific:
- Routes: `/actuator/gateway/routes`

## 🔐 Certificate Details

| File | Purpose | Used By |
|------|---------|---------|
| `root-ca.pem` | Root Certificate Authority | Both sides |
| `middleware-keystore.p12` | Server certificate | mTLS Middleware |
| `middleware-truststore.p12` | Client cert validation | mTLS Middleware |
| `client-keystore.p12` | Client certificate | User BFF |
| `client-truststore.p12` | Server cert validation | User BFF |

Password: `changeit` (configurable)

## ⚠️ Security Notes

1. **Change default passwords** in production
2. **Restrict `admin_cidr`** to your IP only
3. **Use private subnets** for internal services in production
4. **Enable CloudWatch** logging for audit trails
5. **Rotate certificates** regularly

## 🐛 Troubleshooting

### Check Service Logs
```bash
ssh -i key.pem ubuntu@INSTANCE_IP
sudo journalctl -u SERVICE_NAME -f
# or
sudo tail -f /var/log/SERVICE_NAME/SERVICE_NAME.log
```

### Check Service Status
```bash
sudo systemctl status config-server
sudo systemctl status eureka-server
# etc.
```

### Verify mTLS
```bash
# From middleware server, check for client cert logging
sudo grep "Client Subject DN" /var/log/mtls-middleware/mtls-middleware.log
```

### Common Issues

1. **Services not starting**: Check cloud-init logs
   ```bash
   sudo cat /var/log/user-data.log
   ```

2. **mTLS failures**: Verify certificates
   ```bash
   openssl x509 -in /opt/SERVICE/certs/cert.pem -noout -subject -serial
   ```

3. **Discovery issues**: Check Eureka dashboard
   ```
   http://EUREKA_IP:8761
   ```

## 📝 License

MIT License - see [LICENSE](LICENSE) file.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to the branch
5. Open a Pull Request

---

Built with ❤️ using Spring Boot, Netflix OSS, and Terraform
