package com.example.ledger.contracts;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.*;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

public final class Contracts {
    private Contracts() {}
    public enum TransactionType { SALE, PURCHASE, REFUND }

    public record PostingRequest(
            @NotBlank @Size(max = 80) String reference,
            @NotNull @DecimalMin("0.01") @Digits(integer = 12, fraction = 2) BigDecimal amount,
            @NotBlank @Pattern(regexp = "INR|USD|EUR") String currency,
            @NotNull TransactionType transactionType,
            @Size(max = 500) String narration) {
        public PostingRequest {
            reference = reference == null ? null : reference.strip();
            amount = amount == null ? null : amount.stripTrailingZeros();
            currency = currency == null ? null : currency.strip().toUpperCase(Locale.ROOT);
            narration = narration == null ? "" : narration.strip();
        }
    }

    public record DecisionRequest(@NotNull TransactionType transactionType,
                                  @NotNull @DecimalMin("0.01") BigDecimal amount,
                                  @NotBlank @Pattern(regexp = "INR|USD|EUR") String currency) {}

    public record AccountDecision(String accountCode, String accountName, String ruleId, String ruleVersion) {}

    public record Posting(UUID id, String reference,
                          @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
                          String currency, TransactionType transactionType, String narration,
                          String accountCode, String accountName, String ruleId, String ruleVersion,
                          Instant createdAt) {}

    public record CurrencyTotal(String currency,
                                @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount) {}
    public record Dashboard(long totalPostings, List<CurrencyTotal> totals, List<Posting> recentPostings) {}
}
