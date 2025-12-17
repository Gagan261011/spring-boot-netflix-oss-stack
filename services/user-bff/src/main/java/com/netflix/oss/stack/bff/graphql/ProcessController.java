package com.netflix.oss.stack.bff.graphql;

import com.netflix.oss.stack.bff.model.MiddlewareResponse;
import com.netflix.oss.stack.bff.model.ProcessRequest;
import com.netflix.oss.stack.bff.service.MiddlewareClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

@Controller
public class ProcessController {

    private static final Logger logger = LoggerFactory.getLogger(ProcessController.class);

    @Autowired
    private MiddlewareClient middlewareClient;

    @QueryMapping
    public String health() {
        return "GraphQL API is healthy";
    }

    @MutationMapping
    public ProcessedResponse process(
            @Argument String type,
            @Argument String message,
            @Argument Double amount) {
        
        logger.info("GraphQL API - Received process mutation: type={}, message={}, amount={}", type, message, amount);

        // Create request and call middleware via mTLS
        ProcessRequest request = new ProcessRequest(type, message, amount);
        MiddlewareResponse middlewareResponse = middlewareClient.callMiddleware(request);

        // Convert to GraphQL response type
        ProcessedResponse response = new ProcessedResponse();
        
        var backend = middlewareResponse.getBackendResponse();
        if (backend != null) {
            response.setRequestId(backend.getRequestId());
            response.setOriginalType(backend.getOriginalType());
            response.setOriginalMessage(backend.getOriginalMessage());
            response.setOriginalAmount(backend.getOriginalAmount());
            response.setComputedOutput(backend.getComputedOutput());
            response.setProcessedBy(backend.getProcessedBy());
            response.setInstanceInfo(backend.getInstanceInfo());
            response.setTimestamp(backend.getTimestamp());
        }
        
        response.setClientCertSubject(middlewareResponse.getClientCertSubject());
        response.setClientCertSerial(middlewareResponse.getClientCertSerial());
        response.setMiddlewareProcessed(middlewareResponse.isMiddlewareProcessed());

        logger.info("GraphQL API - Response with cert subject: {}", response.getClientCertSubject());
        return response;
    }
}
