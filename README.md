# High Availability Multi-Region Architecture Explanation

## 🏗️ Architecture Overview

This Terraform configuration creates a highly available, multi-region API architecture with automatic failover capabilities. Here's how each component works:

## Architecture Diagram

```mermaid
graph TB
    subgraph "Internet"
        Client[Client Applications]
        Browser[Web Browser]
    end

    subgraph "DNS & Routing"
        Route53[Route 53 Hosted Zone<br/>ponmile.com.ng]
        HealthCheck1[Health Check<br/>Primary Region]
        HealthCheck2[Health Check<br/>Secondary Region]
    end

    subgraph "Primary Region (us-east-1)"
        subgraph "API Gateway Primary"
            AGW1[API Gateway REST API<br/>REGIONAL Endpoint]
            Domain1[Custom Domain<br/>api.ponmile.com.ng]
            Cert1[ACM Certificate<br/>Primary Region]
        end
        
        subgraph "Lambda Functions Primary"
            ReadLambda1[Read Function<br/>Python 3.9]
            WriteLambda1[Write Function<br/>Python 3.9]
        end
        
        subgraph "Database Primary"
            DDB1[DynamoDB Table<br/>PAY_PER_REQUEST<br/>Streams Enabled]
        end
    end

    subgraph "Secondary Region (us-west-2)"
        subgraph "API Gateway Secondary"
            AGW2[API Gateway REST API<br/>REGIONAL Endpoint]
            Domain2[Custom Domain<br/>api.ponmile.com.ng]
            Cert2[ACM Certificate<br/>Secondary Region]
        end
        
        subgraph "Lambda Functions Secondary"
            ReadLambda2[Read Function<br/>Python 3.9]
            WriteLambda2[Write Function<br/>Python 3.9]
        end
        
        subgraph "Database Secondary"
            DDB2[DynamoDB Table<br/>PAY_PER_REQUEST<br/>Streams Enabled]
        end
    end

    subgraph "Global Services"
        GlobalTable[DynamoDB Global Table<br/>Cross-Region Replication]
        S3Frontend[S3 Static Website<br/>Frontend Hosting]
    end

    subgraph "IAM & Security"
        LambdaRole[Lambda Execution Role]
        DDBPolicy[DynamoDB Access Policy]
    end

    %% Client connections
    Client --> Route53
    Browser --> S3Frontend

    %% DNS routing with health checks
    Route53 --> |PRIMARY - Healthy| Domain1
    Route53 --> |SECONDARY - Failover| Domain2
    HealthCheck1 --> AGW1
    HealthCheck2 --> AGW2

    %% API Gateway to Lambda connections
    Domain1 --> AGW1
    Domain2 --> AGW2
    AGW1 --> |/read GET| ReadLambda1
    AGW1 --> |/write POST| WriteLambda1
    AGW2 --> |/read GET| ReadLambda2
    AGW2 --> |/write POST| WriteLambda2

    %% Lambda to DynamoDB connections
    ReadLambda1 --> DDB1
    WriteLambda1 --> DDB1
    ReadLambda2 --> DDB2
    WriteLambda2 --> DDB2

    %% Global table replication
    DDB1 <--> |Bi-directional<br/>Replication| GlobalTable
    DDB2 <--> |Bi-directional<br/>Replication| GlobalTable

    %% Certificate dependencies
    Cert1 --> Domain1
    Cert2 --> Domain2

    %% IAM connections
    LambdaRole --> ReadLambda1
    LambdaRole --> WriteLambda1
    LambdaRole --> ReadLambda2
    LambdaRole --> WriteLambda2
    DDBPolicy --> LambdaRole

    %% Styling
    classDef primaryRegion fill:#e1f5fe
    classDef secondaryRegion fill:#f3e5f5
    classDef globalService fill:#e8f5e8
    classDef client fill:#fff3e0
    classDef dns fill:#fce4ec

    class AGW1,Domain1,Cert1,ReadLambda1,WriteLambda1,DDB1 primaryRegion
    class AGW2,Domain2,Cert2,ReadLambda2,WriteLambda2,DDB2 secondaryRegion
    class GlobalTable,S3Frontend,LambdaRole,DDBPolicy globalService
    class Client,Browser client
    class Route53,HealthCheck1,HealthCheck2 dns
```

## 📍 Traffic Flow

### 1. **Client Request Journey**
```
Client → Route 53 → Health Check → API Gateway → Lambda → DynamoDB
```

### 2. **DNS-Based Failover**
- **Primary Route**: Route 53 directs traffic to Primary Region (us-east-1)
- **Health Monitoring**: Continuous health checks on both regions
- **Automatic Failover**: Traffic switches to Secondary Region (us-west-2) if primary fails
- **Recovery**: Traffic returns to primary when it's healthy again

## 🔧 Key Components

### **Route 53 DNS Management**
- **Hosted Zone**: Manages `ponmile.com.ng` domain
- **Health Checks**: Monitor API endpoints every 30 seconds
- **Failover Policy**: 
  - PRIMARY record points to us-east-1
  - SECONDARY record points to us-west-2
- **Automatic Switching**: DNS responds with healthy endpoint

### **API Gateway (Regional Endpoints)**
- **Regional Deployment**: Deployed in both regions for low latency
- **Custom Domain**: `api.ponmile.com.ng` maps to both regions
- **CORS Enabled**: Supports cross-origin requests
- **Endpoints**:
  - `GET /read` - Retrieve data
  - `POST /write` - Store data
  - `OPTIONS` - CORS preflight

### **Lambda Functions**
- **Serverless Compute**: Auto-scaling, pay-per-use
- **Identical Deployment**: Same functions in both regions
- **Environment Variables**: Table name configuration
- **IAM Permissions**: Access to DynamoDB in respective regions

### **DynamoDB Global Tables**
- **Multi-Region Replication**: Data synced between regions
- **Bi-directional Sync**: Changes replicate both ways
- **Eventually Consistent**: Data consistency across regions
- **Streams Enabled**: Captures data changes for replication

### **SSL/TLS Certificates**
- **Regional Certificates**: ACM certificates in each region
- **DNS Validation**: Automated certificate validation
- **Auto-Renewal**: AWS manages certificate lifecycle

## 🔄 How Failover Works

### **Normal Operation (Primary Active)**
1. Client queries `api.ponmile.com.ng`
2. Route 53 returns Primary Region IP (us-east-1)
3. Request goes to Primary API Gateway
4. Lambda processes request using Primary DynamoDB
5. Data changes replicate to Secondary Region

### **Failover Scenario (Primary Down)**
1. Health check detects Primary Region failure
2. Route 53 marks Primary as unhealthy
3. New DNS queries return Secondary Region IP (us-west-2)
4. Existing connections may need to retry
5. Secondary Region serves all traffic
6. Data remains available via replicated DynamoDB

### **Recovery (Primary Restored)**
1. Health check detects Primary Region recovery
2. Route 53 marks Primary as healthy
3. New DNS queries return Primary Region IP
4. Traffic gradually shifts back to Primary
5. Normal operation resumes

## 🎯 Benefits of This Architecture

### **High Availability**
- **99.9%+ Uptime**: Multiple failure points eliminated
- **Regional Redundancy**: Survives entire region outages
- **Health Monitoring**: Automatic failure detection

### **Performance**
- **Regional Endpoints**: Reduced latency via geographic proximity
- **Serverless Scaling**: Auto-scales with demand
- **CDN Ready**: S3 frontend can integrate with CloudFront

### **Data Consistency**
- **Global Tables**: Data available in both regions
- **Stream-based Replication**: Near real-time data sync
- **No Data Loss**: Writes replicate automatically

### **Cost Optimization**
- **Pay-per-Use**: Lambda and DynamoDB scale to zero
- **Regional Deployment**: Optimize costs by region
- **Efficient Routing**: Minimize cross-region data transfer

## 🛠️ Key Configuration Details

### **API Gateway Domain Fix**
The original issue was resolved by using:
```hcl
regional_certificate_arn = aws_acm_certificate.primary.arn
```
Instead of:
```hcl
certificate_arn = aws_acm_certificate.primary.arn
```

### **CORS Configuration**
- Enables web browser access from any origin
- Supports standard HTTP methods
- Handles preflight OPTIONS requests

### **IAM Security**
- Least privilege access for Lambda functions
- DynamoDB permissions scoped to specific tables
- Cross-region access properly configured

## 🚀 Deployment Considerations

1. **Certificate Validation**: Ensure DNS records for ACM validation
2. **Domain Ownership**: Route 53 hosted zone must exist
3. **Lambda Code**: Upload actual function code to `/lambda/` directory
4. **Frontend**: Upload HTML files to `/frontend/` directory
5. **Testing**: Verify health checks after deployment

This architecture provides enterprise-grade reliability with automatic failover, making it suitable for production workloads requiring high availability.
