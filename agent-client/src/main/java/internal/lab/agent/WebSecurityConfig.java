package internal.lab.agent;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;

/**
 * P6.3: ONE interface — the console at the root. The shell and /api/me are
 * public (the console renders logged-out and offers the login); chatting is
 * authenticated. Every login ENDS at the console root, no matter what request
 * Spring saved along the way (alwaysUse — the saved-request default burned us
 * twice). alice's tokens live in the server-side session; the browser holds a
 * cookie (check-p25/check-p6 prove it).
 *
 * CSRF uses the plain request-attribute handler: the console reads the raw
 * token from /api/me and echoes it in X-CSRF-TOKEN (the XOR handler would
 * reject a raw token; BREACH masking buys nothing in this lab).
 */
@Configuration
@Profile("web")
public class WebSecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        CsrfTokenRequestAttributeHandler plainCsrf = new CsrfTokenRequestAttributeHandler();
        http
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/api/chat", "/api/chat/stream").authenticated()
                        .anyRequest().permitAll())
                .csrf(csrf -> csrf.csrfTokenRequestHandler(plainCsrf))
                .oauth2Login(login -> login.defaultSuccessUrl("/", true))
                .logout(logout -> logout.logoutSuccessUrl("/"));
        return http.build();
    }
}
