package com.example.ledger.posting;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;
import com.example.ledger.contracts.Contracts.*;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.web.server.ResponseStatusException;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class PostingIntegrationTest {
    @Container @ServiceConnection
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:18-alpine");
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired JdbcTemplate jdbc;
    @Autowired PostingService service;
    @Autowired PostingRepository repository;
    @MockitoBean RulesClient rules;

    @BeforeEach void resetDatabase() {
        jdbc.execute("truncate table postings");
        when(rules.decide(any())).thenReturn(new AccountDecision("DEMO-4001", "Demo sales", "SALE_ACCOUNT", "test-v1"));
    }

    private PostingRequest request(String reference, String amount, String currency) {
        return new PostingRequest(reference, new BigDecimal(amount), currency, TransactionType.SALE, "Sample posting");
    }

    @Test void retryReturnsTheSamePostingAndPreservesDecimalPrecision() throws Exception {
        String key = UUID.randomUUID().toString();
        byte[] body = json.writeValueAsBytes(request("SALE-001", "123.45", "INR"));
        String first = mvc.perform(post("/api/postings").header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.amount").value("123.45"))
                .andExpect(jsonPath("$.ruleVersion").value("test-v1")).andReturn().getResponse().getContentAsString();
        String replay = mvc.perform(post("/api/postings").header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(header().string("Idempotency-Replayed", "true"))
                .andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(replay).get("id")).isEqualTo(json.readTree(first).get("id"));
        assertThat(repository.dashboard().totalPostings()).isEqualTo(1);
        verify(rules, times(1)).decide(any());
    }

    @Test void reusingTheKeyWithDifferentFieldsIsRejected() throws Exception {
        UUID key = UUID.randomUUID();
        service.create(key, request("SALE-002", "10.00", "INR"));
        mvc.perform(post("/api/postings").header("Idempotency-Key", key)
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(request("SALE-002", "20.00", "INR"))))
                .andExpect(status().isConflict());
        assertThat(repository.dashboard().totalPostings()).isEqualTo(1);
    }

    @Test void failedRulesDoNotSaveAPosting() throws Exception {
        when(rules.decide(any())).thenThrow(new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Rules unavailable"));
        mvc.perform(post("/api/postings").header("Idempotency-Key", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(request("SALE-003", "10.00", "INR"))))
                .andExpect(status().isServiceUnavailable());
        assertThat(repository.dashboard().totalPostings()).isZero();
    }

    @Test void invalidAmountIsRejectedBeforeCallingRules() throws Exception {
        mvc.perform(post("/api/postings").header("Idempotency-Key", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsBytes(request("SALE-004", "0", "INR"))))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(rules);
    }

    @Test void concurrentIdenticalRequestsCreateExactlyOneRow() throws Exception {
        UUID key = UUID.randomUUID();
        var futures = new ArrayList<Future<UUID>>();
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 6; i++) {
                futures.add(executor.submit(() -> service.create(key, request("RACE-001", "20.00", "INR")).posting().id()));
            }
            var ids = new ArrayList<UUID>();
            for (var future : futures) ids.add(future.get(30, TimeUnit.SECONDS));
            assertThat(ids).containsOnly(ids.getFirst());
        }
        assertThat(repository.dashboard().totalPostings()).isEqualTo(1);
    }

    @Test void dashboardKeepsCurrenciesSeparate() {
        service.create(UUID.randomUUID(), request("INR-001", "10.10", "INR"));
        service.create(UUID.randomUUID(), request("USD-001", "20.20", "USD"));
        service.create(UUID.randomUUID(), request("INR-002", "30.30", "INR"));
        var dashboard = repository.dashboard();
        assertThat(dashboard.totalPostings()).isEqualTo(3);
        assertThat(dashboard.totals()).containsExactly(new CurrencyTotal("INR", new BigDecimal("40.40")),
                new CurrencyTotal("USD", new BigDecimal("20.20")));
    }
}
