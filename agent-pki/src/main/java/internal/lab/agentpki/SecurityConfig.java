package internal.lab.agentpki;

import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final String issuerUri;
    private final String jwkSetUri;
    private final String resourceId;

    public SecurityConfig(
            @Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuerUri,
            @Value("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}") String jwkSetUri,
            @Value("${pki.resource-id}") String resourceId) {
        this.issuerUri = issuerUri;
        this.jwkSetUri = jwkSetUri;
        this.resourceId = resourceId;
    }

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, ResourceMetadataEntryPoint entryPoint) throws Exception {
        http.authorizeHttpRequests(auth -> auth
                        .requestMatchers("/.well-known/**").permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(rs -> rs
                        .jwt(Customizer.withDefaults())
                        .authenticationEntryPoint(entryPoint)
                        // Spring Security 7.1 serves RFC 9728 metadata itself
                        // (OAuth2ProtectedResourceMetadataFilter); by default it
                        // derives `resource` from the request URL — override with
                        // the canonical identifier (D-005) and advertise the AS.
                        .protectedResourceMetadata(md -> md.protectedResourceMetadataCustomizer(builder -> builder
                                .resource(resourceId)
                                .authorizationServer(issuerUri)
                                .bearerMethod("header"))))
                .exceptionHandling(ex -> ex.authenticationEntryPoint(entryPoint));
        return http.build();
    }

    /**
     * The anti-passthrough rule: a token is valid here ONLY if its {@code aud}
     * contains this server's resource identifier. Rejecting everything else is
     * the M4 exit criterion that matters more than the happy path.
     */
    @Bean
    JwtDecoder jwtDecoder() {
        // withJwkSetUri, not withIssuerLocation: the latter performs OIDC discovery
        // at bean construction, and the lab realm is provisioned after container
        // start. iss is still validated below against the configured issuer.
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        OAuth2TokenValidator<Jwt> audienceValidator = jwt -> {
            List<String> audience = jwt.getAudience();
            if (audience != null && audience.contains(resourceId)) {
                return OAuth2TokenValidatorResult.success();
            }
            return OAuth2TokenValidatorResult.failure(new OAuth2Error(
                    "invalid_token",
                    "aud must contain " + resourceId,
                    null));
        };
        decoder.setJwtValidator(new org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(issuerUri),
                audienceValidator));
        return decoder;
    }

    /** RFC 9728 §5.1: 401 responses carry the resource_metadata pointer. */
    @Bean
    ResourceMetadataEntryPoint resourceMetadataEntryPoint() {
        return new ResourceMetadataEntryPoint(resourceId, new BearerTokenAuthenticationEntryPoint());
    }
}
