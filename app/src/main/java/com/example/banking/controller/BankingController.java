package com.example.banking.controller;

import com.example.banking.ShutdownListener;
import com.example.banking.dto.DepositRequest;
import com.example.banking.entity.Account;
import com.example.banking.entity.Transaction;
import com.example.banking.repository.AccountRepository;
import com.example.banking.repository.TransactionRepository;
import com.example.banking.service.BankingService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.net.InetAddress;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api")
@CrossOrigin(origins = "*")
@RequiredArgsConstructor
public class BankingController {
    
    private final BankingService bankingService;
    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    
    @GetMapping("/health/ready")
    public ResponseEntity<Map<String, Object>> readiness() {
        Map<String, Object> response = new HashMap<>();
        boolean ready = ShutdownListener.isReady();
        response.put("status", ready ? "UP" : "DOWN");
        response.put("ready", ready);
        return ready ? ResponseEntity.ok(response) : ResponseEntity.status(503).body(response);
    }
    
    @GetMapping("/drain")
    public ResponseEntity<Map<String, String>> drain() {
        // PreStop Hook: Ngừng nhận traffic mới ngay lập tức
        ShutdownListener.setNotReady();
        
        Map<String, String> response = new HashMap<>();
        response.put("status", "draining");
        response.put("message", "Pod is draining - readiness set to FALSE");
        response.put("action", "No new traffic will be accepted");
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/pod-info")
    public Map<String, String> getPodInfo() {
        Map<String, String> info = new HashMap<>();
        try {
            info.put("podIp", InetAddress.getLocalHost().getHostAddress());
            info.put("podName", System.getenv().getOrDefault("HOSTNAME", "unknown"));
        } catch (Exception e) {
            info.put("error", e.getMessage());
        }
        return info;
    }
    
    @GetMapping("/accounts")
    public List<Account> getAllAccounts() {
        return accountRepository.findAll();
    }
    
    @GetMapping("/transactions")
    public List<Transaction> getAllTransactions() {
        return transactionRepository.findAllByOrderByCreatedAtDesc();
    }
    
    @PostMapping("/deposit")
    public ResponseEntity<?> deposit(@RequestBody DepositRequest request) {
        try {
            Transaction transaction = bankingService.deposit(
                    request.getAccountNumber(), 
                    request.getAmount()
            );
            return ResponseEntity.ok(transaction);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
