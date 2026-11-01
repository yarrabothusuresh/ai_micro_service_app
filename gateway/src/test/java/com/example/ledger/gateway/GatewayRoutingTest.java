package com.example.ledger.gateway;

import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.reactive.server.WebTestClient;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GatewayRoutingTest {
    private static final HttpServer BACKEND = backend();
    @LocalServerPort int port;
    WebTestClient client;
    @BeforeEach void realHttpClient() {
        client = WebTestClient.bindToServer().baseUrl("http://127.0.0.1:" + port).build();
    }

    private static HttpServer backend() {
        try {
            var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/", exchange -> {
                boolean suppliedToken = exchange.getRequestHeaders().containsKey("X-Serverless-Authorization");
                String text = "{\"path\":\"" + exchange.getRequestURI().getPath() + "\",\"suppliedToken\":" + suppliedToken + "}";
                byte[] body = text.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Content-Type", "application/json");
                exchange.sendResponseHeaders(200, body.length);
                try (var output = exchange.getResponseBody()) { output.write(body); }
            });
            server.start();
            return server;
        } catch (IOException exception) { throw new ExceptionInInitializerError(exception); }
    }

    @DynamicPropertySource
    static void destinations(DynamicPropertyRegistry properties) {
        String url = "http://127.0.0.1:" + BACKEND.getAddress().getPort();
        properties.add("services.ui-url", () -> url);
        properties.add("services.posting-url", () -> url);
        properties.add("services.frontend-origins", () -> "http://localhost:5173,http://127.0.0.1:5173");
    }
    @AfterAll static void closeBackend() { BACKEND.stop(0); }

    @Test void routesDashboardAndPreservesItsPath() {
        client.get().uri("/api/ui/dashboard").exchange().expectStatus().isOk()
                .expectHeader().exists("X-Correlation-ID")
                .expectBody().jsonPath("$.path").isEqualTo("/api/ui/dashboard");
    }
    @Test void identifiesThePublishedApiAtTheRoot() {
        client.get().uri("/").exchange().expectStatus().isOk()
                .expectBody().jsonPath("$.application").isEqualTo("Ledger Manager API")
                .jsonPath("$.postings").isEqualTo("/api/postings");
    }
    @Test void routesPostingWithoutTrustingCallerSuppliedPlatformIdentity() {
        client.post().uri("/api/postings").header("X-Serverless-Authorization", "Bearer untrusted")
                .contentType(MediaType.APPLICATION_JSON).bodyValue("{}").exchange().expectStatus().isOk()
                .expectBody().jsonPath("$.path").isEqualTo("/api/postings")
                .jsonPath("$.suppliedToken").isEqualTo(false);
    }
    @Test void doesNotExposeTheInternalDecisionEndpoint() {
        client.post().uri("/internal/decisions").exchange().expectStatus().isNotFound();
    }
    @Test void allowsTheConfiguredFrontendOrigin() {
        client.options().uri("/api/postings").header("Origin", "http://localhost:5173")
                .header("Access-Control-Request-Method", "POST")
                .header("Access-Control-Request-Headers", "Idempotency-Key,Content-Type")
                .exchange().expectStatus().isOk()
                .expectHeader().valueEquals("Access-Control-Allow-Origin", "http://localhost:5173");
    }
    @Test void rejectsAnUnconfiguredBrowserOrigin() {
        client.options().uri("/api/postings").header("Origin", "https://untrusted.example")
                .header("Access-Control-Request-Method", "POST").exchange().expectStatus().isForbidden();
    }
}
