package com.example.ledger.posting;

import com.example.ledger.contracts.Contracts.*;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
public class PostingController {
    private final PostingService service;
    private final PostingRepository repository;
    public PostingController(PostingService service, PostingRepository repository) {
        this.service = service; this.repository = repository;
    }
    @PostMapping("/api/postings")
    public ResponseEntity<Posting> create(@RequestHeader("Idempotency-Key") UUID key,
                                         @Valid @RequestBody PostingRequest request) {
        var result = service.create(key, request);
        return ResponseEntity.status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .location(URI.create("/api/postings/" + result.posting().id()))
                .header("Idempotency-Replayed", Boolean.toString(!result.created())).body(result.posting());
    }
    @GetMapping("/api/postings")
    public List<Posting> recent() { return repository.recent(50); }

    @GetMapping("/api/postings/{id}")
    public Posting byId(@PathVariable UUID id) {
        return repository.byId(id).orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Posting not found"));
    }
    @GetMapping("/internal/postings/dashboard")
    public Dashboard dashboard() { return repository.dashboard(); }
}
