package com.example.banking.service;

import com.example.banking.entity.Account;
import com.example.banking.entity.Transaction;
import com.example.banking.repository.AccountRepository;
import com.example.banking.repository.TransactionRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.math.BigDecimal;

@Slf4j
@Service
@RequiredArgsConstructor
public class BankingService {
    
    private final AccountRepository accountRepository;
    private final TransactionRepository transactionRepository;
    
    @Transactional
    public Transaction deposit(String accountNumber, BigDecimal amount) {
        log.info("🔵 [START] Deposit transaction for account: {}, amount: {}", accountNumber, amount);
        
        // Step 1: Create transaction with PROCESSING status
        Transaction transaction = new Transaction();
        transaction.setAccountNumber(accountNumber);
        transaction.setType("DEPOSIT");
        transaction.setAmount(amount);
        transaction.setStatus("PROCESSING");
        transaction = transactionRepository.save(transaction);
        log.info("📝 [STEP 1] Transaction created with ID: {}, status: PROCESSING", transaction.getId());
        
        try {
            // Step 2: Simulate slow processing (10 seconds)
            log.info("⏳ [STEP 2] Processing transaction... (sleeping 10 seconds)");
            Thread.sleep(10000);
            log.info("✅ [STEP 2] Processing completed");
            
            // Step 3: Lock and update account balance
            log.info("🔒 [STEP 3] Acquiring lock on account: {}", accountNumber);
            Account account = accountRepository.findByAccountNumberWithLock(accountNumber)
                    .orElseThrow(() -> new RuntimeException("Account not found: " + accountNumber));
            
            BigDecimal oldBalance = account.getBalance();
            account.setBalance(oldBalance.add(amount));
            accountRepository.save(account);
            log.info("💰 [STEP 3] Balance updated: {} -> {}", oldBalance, account.getBalance());
            
            // Step 4: Update transaction status to COMPLETED
            transaction.setStatus("COMPLETED");
            transaction = transactionRepository.save(transaction);
            log.info("✅ [STEP 4] Transaction completed with ID: {}", transaction.getId());
            
            log.info("🟢 [SUCCESS] Deposit transaction completed successfully");
            return transaction;
            
        } catch (InterruptedException e) {
            log.error("❌ [ERROR] Transaction interrupted: {}", e.getMessage());
            transaction.setStatus("FAILED");
            transactionRepository.save(transaction);
            Thread.currentThread().interrupt();
            throw new RuntimeException("Transaction interrupted", e);
        } catch (Exception e) {
            log.error("❌ [ERROR] Transaction failed: {}", e.getMessage());
            transaction.setStatus("FAILED");
            transactionRepository.save(transaction);
            throw e;
        }
    }
}
