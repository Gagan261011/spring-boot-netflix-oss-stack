package com.netflix.oss.stack.backend.controller;

import com.netflix.oss.stack.backend.model.ProcessRequest;
import com.netflix.oss.stack.backend.model.ProcessResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

import java.net.InetAddress;
import java.time.Instant;
import java.util.UUID;

@RestController
@RequestMapping("/backend")
public class BackendController {

    @Value("${spring.application.name}")
    private String applicationName;

    @PostMapping("/process")
    public ProcessResponse process(
            @RequestBody ProcessRequest request,
            @RequestHeader(value = "X-Client-Subject", required = false) String clientSubject,
            @RequestHeader(value = "X-Client-Serial", required = false) String clientSerial) {
        
        String instanceInfo;
        try {
            instanceInfo = InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            instanceInfo = "unknown";
        }

        // Process the request - compute some output based on input
        String computedOutput = computeOutput(request);

        return ProcessResponse.builder()
                .requestId(UUID.randomUUID().toString())
                .originalType(request.getType())
                .originalMessage(request.getMessage())
                .originalAmount(request.getAmount())
                .computedOutput(computedOutput)
                .processedBy(applicationName)
                .instanceInfo(instanceInfo)
                .timestamp(Instant.now().toString())
                .clientCertSubject(clientSubject)
                .clientCertSerial(clientSerial)
                .build();
    }

    private String computeOutput(ProcessRequest request) {
        double processedAmount = request.getAmount() * 1.1; // 10% processing fee
        return String.format("Processed %s request: '%s' with amount %.2f (processed: %.2f)",
                request.getType(),
                request.getMessage(),
                request.getAmount(),
                processedAmount);
    }

    @GetMapping("/health")
    public String health() {
        return "Backend is healthy";
    }
}
