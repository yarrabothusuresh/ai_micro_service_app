package com.example.ledger.rules;

import com.example.ledger.contracts.ApiErrors;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Import;

@SpringBootApplication
@Import(ApiErrors.class)
public class RulesApplication {
    public static void main(String[] args) { SpringApplication.run(RulesApplication.class, args); }
}
