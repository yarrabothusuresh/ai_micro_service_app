package com.example.ledger.gateway;

import java.util.Arrays;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.reactive.CorsWebFilter;
import org.springframework.web.cors.reactive.UrlBasedCorsConfigurationSource;

@SpringBootApplication
public class GatewayApplication {
    public static void main(String[] args) { SpringApplication.run(GatewayApplication.class, args); }

    @Bean
    RouteLocator routes(RouteLocatorBuilder builder, CloudIdentity identity,
                        @Value("${services.ui-url}") String uiUrl,
                        @Value("${services.posting-url}") String postingUrl) {
        return builder.routes()
                .route("ui-api", route -> route.path("/api/ui", "/api/ui/**")
                        .filters(filters -> filters.filter(identity.forAudience(uiUrl))).uri(uiUrl))
                .route("posting-api", route -> route.path("/api/postings", "/api/postings/**")
                        .filters(filters -> filters.filter(identity.forAudience(postingUrl))).uri(postingUrl))
                .build();
    }

    @Bean
    @Order(Ordered.HIGHEST_PRECEDENCE)
    CorsWebFilter cors(@Value("${services.frontend-origins}") String origins) {
        var config = new CorsConfiguration();
        config.setAllowedOrigins(Arrays.stream(origins.split(",")).map(String::strip).toList());
        config.setAllowedMethods(Arrays.asList("GET", "POST", "OPTIONS"));
        config.setAllowedHeaders(Arrays.asList("Content-Type", "Idempotency-Key", "X-Correlation-ID"));
        config.setExposedHeaders(Arrays.asList("Location", "Idempotency-Replayed", "X-Correlation-ID"));
        config.setMaxAge(3600L);
        var source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return new CorsWebFilter(source);
    }
}
