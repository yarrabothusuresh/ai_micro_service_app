package com.example.ledger.rules;

import com.example.ledger.contracts.Contracts.AccountDecision;
import com.example.ledger.contracts.Contracts.DecisionRequest;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.kie.api.KieBase;
import org.kie.api.builder.Message;
import org.kie.api.io.ResourceType;
import org.kie.internal.io.ResourceFactory;
import org.kie.internal.utils.KieHelper;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AccountRules {
    private final KieBase rules;
    private final String version;
    public AccountRules() throws IOException, NoSuchAlgorithmException {
        byte[] bytes = new ClassPathResource("rules/account-rules.drl.xlsx").getContentAsByteArray();
        version = "excel-" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)).substring(0, 12);
        var resource = ResourceFactory.newByteArrayResource(bytes).setSourcePath("rules/account-rules.drl.xlsx");
        var helper = new KieHelper().addResource(resource, ResourceType.DTABLE);
        var result = helper.verify();
        if (result.hasMessages(Message.Level.ERROR)) {
            throw new IllegalStateException("Excel rules could not be compiled: " + result.getMessages(Message.Level.ERROR));
        }
        rules = helper.build();
    }
    public AccountDecision evaluate(DecisionRequest request) {
        return evaluateType(request.transactionType().name());
    }
    AccountDecision evaluateType(String type) {
        var fact = new DecisionFact(type, version);
        var session = rules.newKieSession();
        try {
            session.insert(fact);
            session.fireAllRules(100);
            if (fact.getDecisions().size() != 1) {
                throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                        "Expected exactly one matching account rule");
            }
            return fact.getDecisions().getFirst();
        } finally { session.dispose(); }
    }
}
