package com.example.ledger.rules;

import com.example.ledger.contracts.Contracts.AccountDecision;
import com.example.ledger.contracts.Contracts.DecisionRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/internal/decisions")
public class RulesController {
    private final AccountRules rules;
    public RulesController(AccountRules rules) { this.rules = rules; }
    @PostMapping
    public AccountDecision evaluate(@Valid @RequestBody DecisionRequest request) { return rules.evaluate(request); }
}
