package com.netflix.oss.stack.middleware.model;

public class BackendResponse {
    private String requestId;
    private String originalType;
    private String originalMessage;
    private double originalAmount;
    private String computedOutput;
    private String processedBy;
    private String instanceInfo;
    private String timestamp;
    private String clientCertSubject;
    private String clientCertSerial;

    public BackendResponse() {}

    // Getters and Setters
    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }
    public String getOriginalType() { return originalType; }
    public void setOriginalType(String originalType) { this.originalType = originalType; }
    public String getOriginalMessage() { return originalMessage; }
    public void setOriginalMessage(String originalMessage) { this.originalMessage = originalMessage; }
    public double getOriginalAmount() { return originalAmount; }
    public void setOriginalAmount(double originalAmount) { this.originalAmount = originalAmount; }
    public String getComputedOutput() { return computedOutput; }
    public void setComputedOutput(String computedOutput) { this.computedOutput = computedOutput; }
    public String getProcessedBy() { return processedBy; }
    public void setProcessedBy(String processedBy) { this.processedBy = processedBy; }
    public String getInstanceInfo() { return instanceInfo; }
    public void setInstanceInfo(String instanceInfo) { this.instanceInfo = instanceInfo; }
    public String getTimestamp() { return timestamp; }
    public void setTimestamp(String timestamp) { this.timestamp = timestamp; }
    public String getClientCertSubject() { return clientCertSubject; }
    public void setClientCertSubject(String clientCertSubject) { this.clientCertSubject = clientCertSubject; }
    public String getClientCertSerial() { return clientCertSerial; }
    public void setClientCertSerial(String clientCertSerial) { this.clientCertSerial = clientCertSerial; }
}
