package com.netflix.oss.stack.bff.rest;

import com.netflix.oss.stack.bff.model.MiddlewareResponse;
import com.netflix.oss.stack.bff.model.ProcessRequest;
import com.netflix.oss.stack.bff.service.MiddlewareClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/rest")
public class RestApiController {

    private static final Logger logger = LoggerFactory.getLogger(RestApiController.class);

    @Autowired
    private MiddlewareClient middlewareClient;

    @PostMapping("/echo")
    public ResponseEntity<MiddlewareResponse> echo(@RequestBody ProcessRequest request) {
        logger.info("REST API - Received echo request: type={}, message={}, amount={}",
                request.getType(), request.getMessage(), request.getAmount());

        // Call middleware via mTLS
        MiddlewareResponse response = middlewareClient.callMiddleware(request);

        logger.info("REST API - Response received with cert subject: {}", response.getClientCertSubject());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("REST API is healthy");
    }
}
