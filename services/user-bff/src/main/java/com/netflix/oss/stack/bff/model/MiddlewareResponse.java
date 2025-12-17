package com.netflix.oss.stack.bff.model;

public class MiddlewareResponse {
    private BackendResponse backendResponse;
    private boolean middlewareProcessed;
    private String clientCertSubject;
    private String clientCertSerial;

    public MiddlewareResponse() {}

    public BackendResponse getBackendResponse() { return backendResponse; }
    public void setBackendResponse(BackendResponse backendResponse) { this.backendResponse = backendResponse; }
    public boolean isMiddlewareProcessed() { return middlewareProcessed; }
    public void setMiddlewareProcessed(boolean middlewareProcessed) { this.middlewareProcessed = middlewareProcessed; }
    public String getClientCertSubject() { return clientCertSubject; }
    public void setClientCertSubject(String clientCertSubject) { this.clientCertSubject = clientCertSubject; }
    public String getClientCertSerial() { return clientCertSerial; }
    public void setClientCertSerial(String clientCertSerial) { this.clientCertSerial = clientCertSerial; }
}
