package com.example.ledger.ui;

import com.example.ledger.contracts.Contracts.Dashboard;
import com.example.ledger.contracts.ServiceHttp;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

@RestController
public class DashboardController {
    private final RestClient posting;
    public DashboardController(@Value("${services.posting-url}") String url,
                               @Value("${services.cloud-auth-enabled:false}") boolean cloudAuth) {
        posting = ServiceHttp.client(url, cloudAuth);
    }
    @GetMapping("/api/ui/dashboard")
    public Dashboard dashboard() {
        var dashboard = posting.get().uri("/internal/postings/dashboard").retrieve().body(Dashboard.class);
        if (dashboard == null) throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Dashboard data unavailable");
        return dashboard;
    }
}
