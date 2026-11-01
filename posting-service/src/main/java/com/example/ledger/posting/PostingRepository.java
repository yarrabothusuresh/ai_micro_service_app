package com.example.ledger.posting;

import com.example.ledger.contracts.Contracts.*;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Repository
public class PostingRepository {
    private final JdbcTemplate jdbc;
    public record StoredPosting(Posting posting, String requestHash) {}
    public record SavedPosting(Posting posting, boolean created) {}
    public PostingRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public Optional<StoredPosting> byKey(UUID key) {
        return jdbc.query("select * from postings where idempotency_key = ?",
                (rs, row) -> new StoredPosting(map(rs), rs.getString("request_hash")), key).stream().findFirst();
    }

    @Transactional(isolation = Isolation.READ_COMMITTED)
    public SavedPosting save(UUID key, String hash, PostingRequest request, AccountDecision decision) {
        UUID id = UUID.randomUUID();
        var inserted = jdbc.query("""
                insert into postings (id, idempotency_key, request_hash, reference, amount, currency,
                    transaction_type, narration, account_code, account_name, rule_id, rule_version)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                on conflict (idempotency_key) do nothing returning *
                """, (rs, row) -> map(rs), id, key, hash, request.reference(), request.amount(), request.currency(),
                request.transactionType().name(), request.narration(), decision.accountCode(), decision.accountName(),
                decision.ruleId(), decision.ruleVersion());
        if (!inserted.isEmpty()) return new SavedPosting(inserted.getFirst(), true);
        var existing = byKey(key).orElseThrow(() -> new IllegalStateException("Concurrent posting could not be read"));
        return new SavedPosting(replay(existing, hash), false);
    }

    public static Posting replay(StoredPosting existing, String hash) {
        if (!existing.requestHash().equals(hash)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This idempotency key was already used with different posting fields");
        }
        return existing.posting();
    }

    public Optional<Posting> byId(UUID id) {
        return jdbc.query("select * from postings where id = ?", (rs, row) -> map(rs), id).stream().findFirst();
    }
    public List<Posting> recent(int limit) {
        return jdbc.query("select * from postings order by created_at desc, id desc limit ?", (rs, row) -> map(rs), limit);
    }

    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ)
    public Dashboard dashboard() {
        long count = jdbc.queryForObject("select count(*) from postings", Long.class);
        var totals = jdbc.query("select currency, sum(amount) as total from postings group by currency order by currency",
                (rs, row) -> new CurrencyTotal(rs.getString("currency"), rs.getBigDecimal("total")));
        return new Dashboard(count, totals, recent(50));
    }
    private static Posting map(ResultSet rs) throws SQLException {
        return new Posting(rs.getObject("id", UUID.class), rs.getString("reference"), rs.getBigDecimal("amount"),
                rs.getString("currency"), TransactionType.valueOf(rs.getString("transaction_type")), rs.getString("narration"),
                rs.getString("account_code"), rs.getString("account_name"), rs.getString("rule_id"),
                rs.getString("rule_version"), rs.getTimestamp("created_at").toInstant());
    }
}
