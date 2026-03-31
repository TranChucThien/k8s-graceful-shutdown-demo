package com.example.banking;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class BankingApplication {
    public static void main(String[] args) {
        System.out.println("=== Banking App v4 ===");
        SpringApplication.run(BankingApplication.class, args);
    }
}
