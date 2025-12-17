package com.netflix.oss.stack.middleware.controller;

import com.netflix.oss.stack.middleware.model.MiddlewareRequest;
import com.netflix.oss.stack.middleware.model.MiddlewareResponse;
import com.netflix.oss.stack.middleware.service.BackendClient;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.security.cert.X509Certificate;

@RestController
@RequestMapping("/middleware")
public class MiddlewareController {

    private static final Logger logger = LoggerFactory.getLogger(MiddlewareController.class);

    @Autowired
    private BackendClient backendClient;

    @PostMapping("/process")
    public MiddlewareResponse process(@RequestBody MiddlewareRequest request, HttpServletRequest httpRequest) {
        // Extract client certificate information
        String clientSubject = "No client certificate";
        String clientSerial = "N/A";

        X509Certificate[] certs = (X509Certificate[]) httpRequest.getAttribute("jakarta.servlet.request.X509Certificate");
        
        if (certs != null && certs.length > 0) {
            X509Certificate clientCert = certs[0];
            clientSubject = clientCert.getSubjectX500Principal().getName();
            clientSerial = clientCert.getSerialNumber().toString(16).toUpperCase();
            
            logger.info("=== mTLS Client Certificate Details ===");
            logger.info("Client Subject DN: {}", clientSubject);
            logger.info("Client Serial Number: {}", clientSerial);
            logger.info("Client Issuer: {}", clientCert.getIssuerX500Principal().getName());
            logger.info("Client Cert Valid From: {}", clientCert.getNotBefore());
            logger.info("Client Cert Valid To: {}", clientCert.getNotAfter());
            logger.info("========================================");
        } else {
            logger.warn("No client certificate provided in the request");
        }

        // Forward request to backend with certificate info in headers
        var backendResponse = backendClient.forwardToBackend(request, clientSubject, clientSerial);

        // Build middleware response with cert info
        return MiddlewareResponse.builder()
                .backendResponse(backendResponse)
                .middlewareProcessed(true)
                .clientCertSubject(clientSubject)
                .clientCertSerial(clientSerial)
                .build();
    }

    @GetMapping("/health")
    public String health() {
        return "Middleware is healthy - mTLS enabled";
    }
}
