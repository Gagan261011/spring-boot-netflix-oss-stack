package com.netflix.oss.stack.bff.service;

import com.netflix.oss.stack.bff.model.MiddlewareResponse;
import com.netflix.oss.stack.bff.model.ProcessRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class MiddlewareClient {

    private static final Logger logger = LoggerFactory.getLogger(MiddlewareClient.class);

    private final RestTemplate mtlsRestTemplate;

    @Value("${middleware.url:https://localhost:8443}")
    private String middlewareUrl;

    public MiddlewareClient(@Qualifier("mtlsRestTemplate") RestTemplate mtlsRestTemplate) {
        this.mtlsRestTemplate = mtlsRestTemplate;
    }

    public MiddlewareResponse callMiddleware(ProcessRequest request) {
        String url = middlewareUrl + "/middleware/process";

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        HttpEntity<ProcessRequest> entity = new HttpEntity<>(request, headers);

        logger.info("Calling middleware via mTLS at: {}", url);
        logger.debug("Request: type={}, message={}, amount={}", 
                request.getType(), request.getMessage(), request.getAmount());

        try {
            MiddlewareResponse response = mtlsRestTemplate.postForObject(url, entity, MiddlewareResponse.class);
            logger.info("Middleware response received successfully");
            return response;
        } catch (Exception e) {
            logger.error("Failed to call middleware: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to call middleware via mTLS", e);
        }
    }
}
