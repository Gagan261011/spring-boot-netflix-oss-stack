package com.netflix.oss.stack.middleware.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.File;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * Certificate Distribution Controller
 * Serves client certificates via HTTP on management port for user-bff to fetch.
 * This runs on the management port (8444) which is HTTP without mTLS requirement.
 */
@RestController
@RequestMapping("/certs")
public class CertificateController {

    private static final Logger logger = LoggerFactory.getLogger(CertificateController.class);

    @Value("${certs.directory:/opt/mtls-middleware/certs}")
    private String certsDirectory;

    /**
     * Serve a certificate file by name.
     * Only allows specific files for security.
     */
    @GetMapping("/{filename:.+}")
    public ResponseEntity<Resource> getCertificate(@PathVariable String filename) {
        // Whitelist of allowed files (only client certs, not server certs or private keys)
        if (!isAllowedFile(filename)) {
            logger.warn("Attempted access to non-whitelisted file: {}", filename);
            return ResponseEntity.notFound().build();
        }

        Path filePath = Paths.get(certsDirectory, filename);
        File file = filePath.toFile();

        if (!file.exists() || !file.isFile()) {
            logger.warn("Certificate file not found: {}", filePath);
            return ResponseEntity.notFound().build();
        }

        // Ensure file is within certs directory (prevent path traversal)
        try {
            if (!file.getCanonicalPath().startsWith(new File(certsDirectory).getCanonicalPath())) {
                logger.warn("Path traversal attempt detected: {}", filename);
                return ResponseEntity.notFound().build();
            }
        } catch (Exception e) {
            logger.error("Error validating file path", e);
            return ResponseEntity.notFound().build();
        }

        logger.info("Serving certificate file: {}", filename);

        Resource resource = new FileSystemResource(file);
        
        HttpHeaders headers = new HttpHeaders();
        headers.setContentDispositionFormData("attachment", filename);
        
        MediaType mediaType = filename.endsWith(".pem") 
            ? MediaType.TEXT_PLAIN 
            : MediaType.APPLICATION_OCTET_STREAM;

        return ResponseEntity.ok()
                .headers(headers)
                .contentType(mediaType)
                .body(resource);
    }

    /**
     * List available certificate files.
     */
    @GetMapping
    public ResponseEntity<String[]> listCertificates() {
        File certsDir = new File(certsDirectory);
        if (!certsDir.exists() || !certsDir.isDirectory()) {
            return ResponseEntity.ok(new String[0]);
        }

        String[] files = certsDir.list((dir, name) -> isAllowedFile(name));
        return ResponseEntity.ok(files != null ? files : new String[0]);
    }

    /**
     * Only allow fetching client certificates, root CA, and truststores.
     * Never expose server private keys or keystores.
     */
    private boolean isAllowedFile(String filename) {
        return filename != null && (
            filename.equals("root-ca.pem") ||
            filename.equals("client-keystore.p12") ||
            filename.equals("client-truststore.p12") ||
            filename.equals("client-cert.pem")
        );
    }
}
