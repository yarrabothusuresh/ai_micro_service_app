package com.example.ledger.rules;

import com.example.ledger.contracts.Contracts.AccountDecision;
import java.util.ArrayList;
import java.util.List;

public class DecisionFact {
    private final String transactionType;
    private final String ruleVersion;
    private final List<AccountDecision> decisions = new ArrayList<>();
    public DecisionFact(String transactionType, String ruleVersion) {
        this.transactionType = transactionType;
        this.ruleVersion = ruleVersion;
    }
    public String getTransactionType() { return transactionType; }
    public List<AccountDecision> getDecisions() { return List.copyOf(decisions); }
    public void select(String code, String name, String ruleId) {
        decisions.add(new AccountDecision(code, name, ruleId, ruleVersion));
    }
}
