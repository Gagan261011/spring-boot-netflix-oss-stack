package com.netflix.oss.stack.middleware.model;

public class MiddlewareResponse {
    private BackendResponse backendResponse;
    private boolean middlewareProcessed;
    private String clientCertSubject;
    private String clientCertSerial;

    public MiddlewareResponse() {}

    private MiddlewareResponse(Builder builder) {
        this.backendResponse = builder.backendResponse;
        this.middlewareProcessed = builder.middlewareProcessed;
        this.clientCertSubject = builder.clientCertSubject;
        this.clientCertSerial = builder.clientCertSerial;
    }

    public static Builder builder() {
        return new Builder();
    }

    public static class Builder {
        private BackendResponse backendResponse;
        private boolean middlewareProcessed;
        private String clientCertSubject;
        private String clientCertSerial;

        public Builder backendResponse(BackendResponse backendResponse) {
            this.backendResponse = backendResponse;
            return this;
        }

        public Builder middlewareProcessed(boolean middlewareProcessed) {
            this.middlewareProcessed = middlewareProcessed;
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

        public MiddlewareResponse build() {
            return new MiddlewareResponse(this);
        }
    }

    // Getters and Setters
    public BackendResponse getBackendResponse() { return backendResponse; }
    public void setBackendResponse(BackendResponse backendResponse) { this.backendResponse = backendResponse; }
    public boolean isMiddlewareProcessed() { return middlewareProcessed; }
    public void setMiddlewareProcessed(boolean middlewareProcessed) { this.middlewareProcessed = middlewareProcessed; }
    public String getClientCertSubject() { return clientCertSubject; }
    public void setClientCertSubject(String clientCertSubject) { this.clientCertSubject = clientCertSubject; }
    public String getClientCertSerial() { return clientCertSerial; }
    public void setClientCertSerial(String clientCertSerial) { this.clientCertSerial = clientCertSerial; }
}
