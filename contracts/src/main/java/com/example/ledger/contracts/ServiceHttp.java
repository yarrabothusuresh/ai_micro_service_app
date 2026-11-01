package com.example.ledger.contracts;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.server.ResponseStatusException;

/** Fixed, administrator-configured destinations; never accept a destination URL from API input. */
public final class ServiceHttp {
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    private static final ConcurrentHashMap<String, Token> TOKENS = new ConcurrentHashMap<>();
    private record Token(String value, Instant refreshAt) {}
    private ServiceHttp() {}

    public static RestClient client(String baseUrl, boolean cloudAuth) {
        var factory = new JdkClientHttpRequestFactory(HTTP);
        factory.setReadTimeout(Duration.ofSeconds(60));
        var builder = RestClient.builder().baseUrl(baseUrl).requestFactory(factory)
                .defaultStatusHandler(status -> status.isError(), (request, response) -> {
                    var status = response.getStatusCode();
                    if (status.value() == 422) {
                        throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                                "Account selection did not produce one valid decision");
                    }
                    throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                            "A required service is unavailable; retry with the same request");
                });
        if (cloudAuth) {
            builder.requestInterceptor((request, body, execution) -> {
                request.getHeaders().set("X-Serverless-Authorization", "Bearer " + identityToken(baseUrl));
                return execution.execute(request, body);
            });
        }
        return builder.build();
    }

    private static String identityToken(String audience) {
        var cached = TOKENS.get(audience);
        if (cached != null && cached.refreshAt().isAfter(Instant.now())) return cached.value();
        try {
            var uri = URI.create("http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience="
                    + URLEncoder.encode(audience, StandardCharsets.UTF_8));
            var request = HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(5))
                    .header("Metadata-Flavor", "Google").GET().build();
            var response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() != 200 || response.body().isBlank()) {
                throw new IOException("Service identity token could not be obtained");
            }
            TOKENS.put(audience, new Token(response.body(), Instant.now().plusSeconds(2700)));
            return response.body();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Service authentication interrupted");
        } catch (IOException exception) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Service authentication unavailable");
        }
    }

    public static ResponseStatusException unavailable(ResourceAccessException exception) {
        return new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE,
                "A required service could not be reached; retry with the same request");
    }
}
