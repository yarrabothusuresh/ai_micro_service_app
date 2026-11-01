package com.example.ledger.gateway;

import java.util.UUID;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.stereotype.Component;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import reactor.core.publisher.Mono;

@Component
public class CorrelationFilter implements GlobalFilter, Ordered {
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        String value = exchange.getRequest().getHeaders().getFirst("X-Correlation-ID");
        String correlation = value != null && value.matches("[a-zA-Z0-9-]{1,64}") ? value : UUID.randomUUID().toString();
        exchange.getResponse().getHeaders().set("X-Correlation-ID", correlation);
        return chain.filter(exchange.mutate().request(request -> request.headers(headers ->
                headers.set("X-Correlation-ID", correlation))).build());
    }
    public int getOrder() { return -100; }
}
