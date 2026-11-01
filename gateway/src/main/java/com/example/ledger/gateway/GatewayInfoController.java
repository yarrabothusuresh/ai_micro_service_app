package com.example.ledger.gateway;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GatewayInfoController {
    @GetMapping("/")
    public Map<String, String> info() {
        return Map.of("application", "Ledger Manager API", "dashboard", "/api/ui/dashboard",
                "postings", "/api/postings", "health", "/actuator/health");
    }
}
