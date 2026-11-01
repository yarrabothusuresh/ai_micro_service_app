package com.example.ledger.posting;

import com.example.ledger.contracts.Contracts.*;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.stereotype.Service;

@Service
public class PostingService {
    private final PostingRepository repository;
    private final RulesClient rules;
    private final ObjectMapper json;
    public PostingService(PostingRepository repository, RulesClient rules, ObjectMapper json) {
        this.repository = repository; this.rules = rules; this.json = json;
    }
    public PostingRepository.SavedPosting create(UUID key, PostingRequest request) {
        String hash = requestHash(request);
        var existing = repository.byKey(key);
        if (existing.isPresent()) {
            return new PostingRepository.SavedPosting(PostingRepository.replay(existing.get(), hash), false);
        }
        // No database transaction is held open while waiting on the rules service.
        var decision = rules.decide(new DecisionRequest(request.transactionType(), request.amount(), request.currency()));
        return repository.save(key, hash, request, decision);
    }
    private String requestHash(PostingRequest request) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(json.writeValueAsBytes(request)));
        } catch (NoSuchAlgorithmException | JsonProcessingException exception) {
            throw new IllegalStateException("Posting request could not be fingerprinted", exception);
        }
    }
}
