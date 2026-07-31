package internal.lab.agent;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;

/**
 * P2.5/P6: the front page and the console shell are public (they offer the
 * login); chatting requires alice's browser session. oauth2Login handles the
 * code + PKCE flow; alice's tokens live in the server-side session — the
 * browser only ever holds the session cookie (check-p25/check-p6 prove it).
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
                        .requestMatchers("/", "/error", "/console/**", "/api/me").permitAll()
                        .anyRequest().authenticated())
                .csrf(csrf -> csrf.csrfTokenRequestHandler(plainCsrf))
                // Login initiated from the console must RETURN to the console —
                // the live panel is the demo surface (P6.2, user-reported).
                .oauth2Login(login -> login.defaultSuccessUrl("/console/"))
                .logout(logout -> logout.logoutSuccessUrl("/console/"));
        return http.build();
    }
}
