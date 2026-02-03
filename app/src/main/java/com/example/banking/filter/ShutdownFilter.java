package com.example.banking.filter;

import com.example.banking.ShutdownListener;
import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import java.io.IOException;

@Slf4j
@Component
public class ShutdownFilter implements Filter {
    
    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) 
            throws IOException, ServletException {
        
        if (!ShutdownListener.isReady()) {
            log.warn("🚫 Rejecting new request - Pod is shutting down");
            HttpServletResponse httpResponse = (HttpServletResponse) response;
            httpResponse.setStatus(503);
            httpResponse.getWriter().write("{\"error\":\"Service Unavailable - Shutting down\"}");
            return;
        }
        
        chain.doFilter(request, response);
    }
}
