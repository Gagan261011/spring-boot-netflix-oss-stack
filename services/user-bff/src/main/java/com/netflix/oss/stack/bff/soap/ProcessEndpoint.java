package com.netflix.oss.stack.bff.soap;

import com.netflix.oss.stack.bff.model.MiddlewareResponse;
import com.netflix.oss.stack.bff.model.ProcessRequest;
import com.netflix.oss.stack.bff.service.MiddlewareClient;
import jakarta.xml.bind.JAXBElement;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.ws.server.endpoint.annotation.Endpoint;
import org.springframework.ws.server.endpoint.annotation.PayloadRoot;
import org.springframework.ws.server.endpoint.annotation.RequestPayload;
import org.springframework.ws.server.endpoint.annotation.ResponsePayload;
import org.w3c.dom.Element;

import javax.xml.namespace.QName;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;

@Endpoint
public class ProcessEndpoint {

    private static final Logger logger = LoggerFactory.getLogger(ProcessEndpoint.class);
    private static final String NAMESPACE_URI = "http://netflix.oss.stack/bff/soap";

    @Autowired
    private MiddlewareClient middlewareClient;

    @PayloadRoot(namespace = NAMESPACE_URI, localPart = "ProcessRequestMessage")
    @ResponsePayload
    public JAXBElement<Element> processRequest(@RequestPayload Element requestElement) {
        logger.info("SOAP Endpoint - Received ProcessRequest");

        try {
            // Parse request
            String type = getElementText(requestElement, "type");
            String message = getElementText(requestElement, "message");
            double amount = Double.parseDouble(getElementText(requestElement, "amount"));

            logger.info("SOAP API - Parsed request: type={}, message={}, amount={}", type, message, amount);

            // Create process request and call middleware
            ProcessRequest processRequest = new ProcessRequest(type, message, amount);
            MiddlewareResponse middlewareResponse = middlewareClient.callMiddleware(processRequest);

            // Build response
            Element responseElement = buildResponseElement(middlewareResponse);
            
            logger.info("SOAP API - Response built with cert subject: {}", middlewareResponse.getClientCertSubject());
            
            return new JAXBElement<>(
                    new QName(NAMESPACE_URI, "ProcessResponseMessage"),
                    Element.class,
                    responseElement);

        } catch (Exception e) {
            logger.error("SOAP API - Error processing request: {}", e.getMessage(), e);
            throw new RuntimeException("SOAP processing error", e);
        }
    }

    private String getElementText(Element parent, String tagName) {
        var nodeList = parent.getElementsByTagNameNS(NAMESPACE_URI, tagName);
        if (nodeList.getLength() == 0) {
            nodeList = parent.getElementsByTagName(tagName);
        }
        if (nodeList.getLength() > 0) {
            return nodeList.item(0).getTextContent();
        }
        return "";
    }

    private Element buildResponseElement(MiddlewareResponse response) throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        DocumentBuilder builder = factory.newDocumentBuilder();
        var doc = builder.newDocument();

        Element root = doc.createElementNS(NAMESPACE_URI, "ProcessResponseMessage");
        doc.appendChild(root);

        var backend = response.getBackendResponse();
        
        appendElement(doc, root, "requestId", backend != null ? backend.getRequestId() : "");
        appendElement(doc, root, "originalType", backend != null ? backend.getOriginalType() : "");
        appendElement(doc, root, "originalMessage", backend != null ? backend.getOriginalMessage() : "");
        appendElement(doc, root, "originalAmount", String.valueOf(backend != null ? backend.getOriginalAmount() : 0));
        appendElement(doc, root, "computedOutput", backend != null ? backend.getComputedOutput() : "");
        appendElement(doc, root, "processedBy", backend != null ? backend.getProcessedBy() : "");
        appendElement(doc, root, "instanceInfo", backend != null ? backend.getInstanceInfo() : "");
        appendElement(doc, root, "timestamp", backend != null ? backend.getTimestamp() : "");
        appendElement(doc, root, "clientCertSubject", response.getClientCertSubject());
        appendElement(doc, root, "clientCertSerial", response.getClientCertSerial());
        appendElement(doc, root, "middlewareProcessed", String.valueOf(response.isMiddlewareProcessed()));

        return root;
    }

    private void appendElement(org.w3c.dom.Document doc, Element parent, String name, String value) {
        Element element = doc.createElementNS(NAMESPACE_URI, name);
        element.setTextContent(value != null ? value : "");
        parent.appendChild(element);
    }
}
