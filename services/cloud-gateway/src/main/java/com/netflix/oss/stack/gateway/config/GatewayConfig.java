package com.netflix.oss.stack.gateway.config;

import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GatewayConfig {

    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
                // REST API route
                .route("user-bff-rest", r -> r
                        .path("/api/rest/**")
                        .uri("lb://USER-BFF"))
                // SOAP/WS route
                .route("user-bff-ws", r -> r
                        .path("/ws/**")
                        .uri("lb://USER-BFF"))
                // GraphQL route
                .route("user-bff-graphql", r -> r
                        .path("/graphql/**")
                        .uri("lb://USER-BFF"))
                // Health check route for BFF
                .route("user-bff-actuator", r -> r
                        .path("/bff/actuator/**")
                        .filters(f -> f.stripPrefix(1))
                        .uri("lb://USER-BFF"))
                .build();
    }
}
