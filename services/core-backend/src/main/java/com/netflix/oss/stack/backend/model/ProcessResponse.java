package com.netflix.oss.stack.backend.model;

public class ProcessResponse {
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

    public ProcessResponse() {}

    private ProcessResponse(Builder builder) {
        this.requestId = builder.requestId;
        this.originalType = builder.originalType;
        this.originalMessage = builder.originalMessage;
        this.originalAmount = builder.originalAmount;
        this.computedOutput = builder.computedOutput;
        this.processedBy = builder.processedBy;
        this.instanceInfo = builder.instanceInfo;
        this.timestamp = builder.timestamp;
        this.clientCertSubject = builder.clientCertSubject;
        this.clientCertSerial = builder.clientCertSerial;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
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

        public Builder requestId(String requestId) {
            this.requestId = requestId;
            return this;
        }

        public Builder originalType(String originalType) {
            this.originalType = originalType;
            return this;
        }

        public Builder originalMessage(String originalMessage) {
            this.originalMessage = originalMessage;
            return this;
        }

        public Builder originalAmount(double originalAmount) {
            this.originalAmount = originalAmount;
            return this;
        }

        public Builder computedOutput(String computedOutput) {
            this.computedOutput = computedOutput;
            return this;
        }

        public Builder processedBy(String processedBy) {
            this.processedBy = processedBy;
            return this;
        }

        public Builder instanceInfo(String instanceInfo) {
            this.instanceInfo = instanceInfo;
            return this;
        }

        public Builder timestamp(String timestamp) {
            this.timestamp = timestamp;
            return this;
        }

        public Builder clientCertSubject(String clientCertSubject) {
            this.clientCertSubject = clientCertSubject;
            return this;
        }

        public Builder clientCertSerial(String clientCertSerial) {
            this.clientCertSerial = clientCertSerial;
            return this;
        }

        public ProcessResponse build() {
            return new ProcessResponse(this);
        }
    }

    // Getters
    public String getRequestId() { return requestId; }
    public String getOriginalType() { return originalType; }
    public String getOriginalMessage() { return originalMessage; }
    public double getOriginalAmount() { return originalAmount; }
    public String getComputedOutput() { return computedOutput; }
    public String getProcessedBy() { return processedBy; }
    public String getInstanceInfo() { return instanceInfo; }
    public String getTimestamp() { return timestamp; }
    public String getClientCertSubject() { return clientCertSubject; }
    public String getClientCertSerial() { return clientCertSerial; }

    // Setters
    public void setRequestId(String requestId) { this.requestId = requestId; }
    public void setOriginalType(String originalType) { this.originalType = originalType; }
    public void setOriginalMessage(String originalMessage) { this.originalMessage = originalMessage; }
    public void setOriginalAmount(double originalAmount) { this.originalAmount = originalAmount; }
    public void setComputedOutput(String computedOutput) { this.computedOutput = computedOutput; }
    public void setProcessedBy(String processedBy) { this.processedBy = processedBy; }
    public void setInstanceInfo(String instanceInfo) { this.instanceInfo = instanceInfo; }
    public void setTimestamp(String timestamp) { this.timestamp = timestamp; }
    public void setClientCertSubject(String clientCertSubject) { this.clientCertSubject = clientCertSubject; }
    public void setClientCertSerial(String clientCertSerial) { this.clientCertSerial = clientCertSerial; }
}
