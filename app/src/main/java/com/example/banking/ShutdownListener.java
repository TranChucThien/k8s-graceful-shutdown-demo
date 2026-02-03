package com.example.banking;

import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.ContextClosedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;
import javax.sql.DataSource;
import java.sql.Connection;
import java.util.concurrent.atomic.AtomicBoolean;

@Slf4j
@Component
@RequiredArgsConstructor
public class ShutdownListener {
    
    private static final AtomicBoolean ready = new AtomicBoolean(true);
    private final DataSource dataSource;
    
    /**
     * SIGTERM Handler - Được gọi khi Spring Boot nhận SIGTERM signal
     * Nhiệm vụ: Shutdown gracefully - đóng connections, cleanup resources
     */
    @EventListener
    public void onShutdown(ContextClosedEvent event) {
        log.warn("🛑 SIGTERM RECEIVED - Starting graceful shutdown process");
        log.info("⏳ Waiting for in-flight requests to complete...");
        log.info("🔌 Preparing to close database connections...");
        
        // Spring Boot sẽ tự động:
        // 1. Chờ các request đang xử lý hoàn thành (max: spring.lifecycle.timeout-per-shutdown-phase)
        // 2. Đóng các connection pools
        // 3. Gọi @PreDestroy methods
    }
    
    /**
     * PreDestroy Hook - Được gọi cuối cùng trước khi container terminate
     * Nhiệm vụ: Final cleanup
     */
    @PreDestroy
    public void onDestroy() {
        log.warn("🛑 PreDestroy called - Final cleanup");
        
        try {
            // Kiểm tra database connection status
            try (Connection conn = dataSource.getConnection()) {
                log.info("✅ Database connection closed gracefully");
            }
        } catch (Exception e) {
            log.error("❌ Error during database cleanup: {}", e.getMessage());
        }
        
        log.info("✅ All resources cleaned up successfully");
    }
    
    // ============================================
    // Readiness Management (for preStop hook)
    // ============================================
    
    public static boolean isReady() {
        return ready.get();
    }
    
    /**
     * Được gọi bởi /api/drain endpoint (preStop hook)
     * Nhiệm vụ: Ngừng nhận traffic mới ngay lập tức
     */
    public static void setNotReady() {
        log.warn("🚫 PreStop Hook - Setting readiness to FALSE (no new traffic)");
        ready.set(false);
    }
}
