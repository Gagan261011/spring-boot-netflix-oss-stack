package com.netflix.oss.stack.bff.config;

import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.client5.http.io.HttpClientConnectionManager;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactory;
import org.apache.hc.client5.http.ssl.SSLConnectionSocketFactoryBuilder;
import org.apache.hc.core5.ssl.SSLContextBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

import javax.net.ssl.SSLContext;
import java.io.File;

@Configuration
public class MtlsClientConfig {

    private static final Logger logger = LoggerFactory.getLogger(MtlsClientConfig.class);

    @Value("${mtls.client.keystore.path:/opt/user-bff/certs/client-keystore.p12}")
    private String keystorePath;

    @Value("${mtls.client.keystore.password:changeit}")
    private String keystorePassword;

    @Value("${mtls.client.truststore.path:/opt/user-bff/certs/client-truststore.p12}")
    private String truststorePath;

    @Value("${mtls.client.truststore.password:changeit}")
    private String truststorePassword;

    @Bean
    public RestTemplate mtlsRestTemplate() {
        try {
            File keystoreFile = new File(keystorePath);
            File truststoreFile = new File(truststorePath);

            logger.info("Loading mTLS keystore from: {}", keystorePath);
            logger.info("Loading mTLS truststore from: {}", truststorePath);

            if (!keystoreFile.exists()) {
                logger.warn("Keystore file not found: {}. Using default RestTemplate.", keystorePath);
                return new RestTemplate();
            }

            if (!truststoreFile.exists()) {
                logger.warn("Truststore file not found: {}. Using default RestTemplate.", truststorePath);
                return new RestTemplate();
            }

            SSLContext sslContext = SSLContextBuilder.create()
                    .loadKeyMaterial(keystoreFile, keystorePassword.toCharArray(), keystorePassword.toCharArray())
                    .loadTrustMaterial(truststoreFile, truststorePassword.toCharArray())
                    .build();

            SSLConnectionSocketFactory sslSocketFactory = SSLConnectionSocketFactoryBuilder.create()
                    .setSslContext(sslContext)
                    .build();

            HttpClientConnectionManager connectionManager = PoolingHttpClientConnectionManagerBuilder.create()
                    .setSSLSocketFactory(sslSocketFactory)
                    .build();

            CloseableHttpClient httpClient = HttpClients.custom()
                    .setConnectionManager(connectionManager)
                    .build();

            HttpComponentsClientHttpRequestFactory requestFactory = new HttpComponentsClientHttpRequestFactory(httpClient);
            requestFactory.setConnectTimeout(10000);

            logger.info("mTLS RestTemplate configured successfully");
            return new RestTemplate(requestFactory);

        } catch (Exception e) {
            logger.error("Failed to configure mTLS RestTemplate: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to configure mTLS client", e);
        }
    }
}
