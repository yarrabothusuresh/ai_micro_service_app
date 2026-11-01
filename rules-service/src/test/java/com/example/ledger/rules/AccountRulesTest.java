package com.example.ledger.rules;

import static org.assertj.core.api.Assertions.*;
import com.example.ledger.contracts.Contracts.DecisionRequest;
import com.example.ledger.contracts.Contracts.TransactionType;
import java.math.BigDecimal;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.springframework.web.server.ResponseStatusException;

class AccountRulesTest {
    private static AccountRules rules;
    @BeforeAll static void compileWorkbook() throws Exception { rules = new AccountRules(); }

    @ParameterizedTest
    @CsvSource({"SALE,DEMO-4001,SALE_ACCOUNT", "PURCHASE,DEMO-5001,PURCHASE_ACCOUNT", "REFUND,DEMO-4002,REFUND_ACCOUNT"})
    void spreadsheetSelectsTheExpectedAccount(TransactionType type, String account, String rule) {
        var decision = rules.evaluate(new DecisionRequest(type, new BigDecimal("123.45"), "INR"));
        assertThat(decision.accountCode()).isEqualTo(account);
        assertThat(decision.ruleId()).isEqualTo(rule);
        assertThat(decision.ruleVersion()).startsWith("excel-");
    }

    @Test void rejectsAnUnmatchedTransaction() {
        assertThatThrownBy(() -> rules.evaluateType("UNKNOWN")).isInstanceOf(ResponseStatusException.class)
                .satisfies(error -> assertThat(((ResponseStatusException) error).getStatusCode().value()).isEqualTo(422));
    }

    @Test void requestsDoNotShareMutableRuleSessions() {
        for (int i = 0; i < 10; i++) {
            assertThat(rules.evaluateType("SALE").accountCode()).isEqualTo("DEMO-4001");
            assertThat(rules.evaluateType("REFUND").accountCode()).isEqualTo("DEMO-4002");
        }
    }
}
