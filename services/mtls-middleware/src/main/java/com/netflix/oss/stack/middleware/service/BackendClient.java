package com.netflix.oss.stack.middleware.service;

import com.netflix.oss.stack.middleware.model.BackendResponse;
import com.netflix.oss.stack.middleware.model.MiddlewareRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

@Service
public class BackendClient {

    private static final Logger logger = LoggerFactory.getLogger(BackendClient.class);

    @Value("${backend.url:http://localhost:8082}")
    private String backendUrl;

    private final RestTemplate restTemplate;

    public BackendClient() {
        this.restTemplate = new RestTemplate();
    }

    public BackendResponse forwardToBackend(MiddlewareRequest request, String clientSubject, String clientSerial) {
        String url = backendUrl + "/backend/process";
        
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Client-Subject", clientSubject);
        headers.set("X-Client-Serial", clientSerial);

        Map<String, Object> body = new HashMap<>();
        body.put("type", request.getType());
        body.put("message", request.getMessage());
        body.put("amount", request.getAmount());

        HttpEntity<Map<String, Object>> entity = new HttpEntity<>(body, headers);

        logger.info("Forwarding request to backend: {} with headers X-Client-Subject={}, X-Client-Serial={}", 
                url, clientSubject, clientSerial);

        return restTemplate.postForObject(url, entity, BackendResponse.class);
    }
}
