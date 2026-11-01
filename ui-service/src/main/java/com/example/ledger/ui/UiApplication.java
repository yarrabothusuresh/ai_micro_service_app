package com.example.ledger.ui;

import com.example.ledger.contracts.ApiErrors;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Import;

@SpringBootApplication
@Import(ApiErrors.class)
public class UiApplication {
    public static void main(String[] args) { SpringApplication.run(UiApplication.class, args); }
}
