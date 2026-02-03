CREATE DATABASE IF NOT EXISTS banking;
USE banking;

CREATE TABLE IF NOT EXISTS accounts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_number VARCHAR(50) NOT NULL UNIQUE,
    account_holder VARCHAR(100) NOT NULL,
    balance DECIMAL(19,2) NOT NULL DEFAULT 0,
    version BIGINT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS transactions (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    account_number VARCHAR(50) NOT NULL,
    type VARCHAR(20) NOT NULL,
    amount DECIMAL(19,2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO accounts (account_number, account_holder, balance, version) VALUES
('ACC001', 'Nguyen Van A', 1000000, 0),
('ACC002', 'Tran Thi B', 2000000, 0),
('ACC003', 'Le Van C', 5000000, 0)
ON DUPLICATE KEY UPDATE account_number=account_number;
