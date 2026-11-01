package com.example.ledger.posting;

import com.example.ledger.contracts.Contracts.AccountDecision;
import com.example.ledger.contracts.Contracts.DecisionRequest;
import com.example.ledger.contracts.ServiceHttp;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

@Component
public class RulesClient {
    private final RestClient client;
    public RulesClient(@Value("${services.rules-url}") String url,
                       @Value("${services.cloud-auth-enabled:false}") boolean cloudAuth) {
        client = ServiceHttp.client(url, cloudAuth);
    }
    public AccountDecision decide(DecisionRequest request) {
        var decision = client.post().uri("/internal/decisions").body(request).retrieve().body(AccountDecision.class);
        if (decision == null || blank(decision.accountCode()) || blank(decision.accountName())
                || blank(decision.ruleId()) || blank(decision.ruleVersion())) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Account selection returned an incomplete decision");
        }
        return decision;
    }
    private static boolean blank(String value) { return value == null || value.isBlank(); }
}
