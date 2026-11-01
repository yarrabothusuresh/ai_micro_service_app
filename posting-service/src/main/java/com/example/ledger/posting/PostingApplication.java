package com.example.ledger.posting;

import com.example.ledger.contracts.ApiErrors;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Import;

@SpringBootApplication
@Import(ApiErrors.class)
public class PostingApplication {
    public static void main(String[] args) { SpringApplication.run(PostingApplication.class, args); }
}
