package com.example.banking.entity;

import jakarta.persistence.*;
import lombok.Data;
import java.math.BigDecimal;

@Data
@Entity
@Table(name = "accounts")
public class Account {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(unique = true, nullable = false)
    private String accountNumber;
    
    @Column(nullable = false)
    private String accountHolder;
    
    @Column(nullable = false)
    private BigDecimal balance = BigDecimal.ZERO;
    
    @Version
    private Long version;
}
