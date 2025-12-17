package com.netflix.oss.stack.middleware;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

@SpringBootApplication
@EnableDiscoveryClient
public class MtlsMiddlewareApplication {
    public static void main(String[] args) {
        SpringApplication.run(MtlsMiddlewareApplication.class, args);
    }
}
