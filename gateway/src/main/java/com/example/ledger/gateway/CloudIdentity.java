package com.example.ledger.gateway;

import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.server.ResponseStatusException;
import reactor.core.publisher.Mono;

/** Adds platform authentication without consuming an end user's Authorization header. */
@Component
public class CloudIdentity {
    private record Token(String value, Instant refreshAt) {}
    private final ConcurrentHashMap<String, Token> tokens = new ConcurrentHashMap<>();
    private final WebClient metadata = WebClient.builder().baseUrl("http://metadata.google.internal").build();
    private final boolean enabled;
    public CloudIdentity(@Value("${services.cloud-auth-enabled:false}") boolean enabled) { this.enabled = enabled; }

    GatewayFilter forAudience(String audience) {
        return (exchange, chain) -> {
            // Incoming clients cannot supply the identity used to invoke our backend.
            var cleaned = exchange.mutate().request(request -> request.headers(headers ->
                    headers.remove("X-Serverless-Authorization"))).build();
            if (!enabled) return chain.filter(cleaned);
            return token(audience).flatMap(token -> chain.filter(cleaned.mutate().request(request ->
                    request.headers(headers -> headers.set("X-Serverless-Authorization", "Bearer " + token))).build()));
        };
    }

    private Mono<String> token(String audience) {
        var cached = tokens.get(audience);
        if (cached != null && cached.refreshAt().isAfter(Instant.now())) return Mono.just(cached.value());
        return metadata.get().uri(builder -> builder
                        .path("/computeMetadata/v1/instance/service-accounts/default/identity")
                        .queryParam("audience", audience).build())
                .header("Metadata-Flavor", "Google").retrieve().bodyToMono(String.class)
                .filter(value -> !value.isBlank())
                .switchIfEmpty(Mono.error(new IllegalStateException("Empty service token")))
                .timeout(Duration.ofSeconds(5))
                .doOnNext(value -> tokens.put(audience, new Token(value, Instant.now().plusSeconds(2700))))
                .onErrorMap(error -> new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                        "Backend service authentication unavailable"));
    }
}
