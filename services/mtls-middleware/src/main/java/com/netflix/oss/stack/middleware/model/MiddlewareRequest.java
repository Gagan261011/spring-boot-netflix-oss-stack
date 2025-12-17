package com.netflix.oss.stack.middleware.model;

public class MiddlewareRequest {
    private String type;
    private String message;
    private double amount;

    public MiddlewareRequest() {}

    public MiddlewareRequest(String type, String message, double amount) {
        this.type = type;
        this.message = message;
        this.amount = amount;
    }

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }
    public String getMessage() { return message; }
    public void setMessage(String message) { this.message = message; }
    public double getAmount() { return amount; }
    public void setAmount(double amount) { this.amount = amount; }
}
