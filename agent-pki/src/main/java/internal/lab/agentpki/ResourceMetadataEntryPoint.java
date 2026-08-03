package internal.lab.agentpki;

import java.io.IOException;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.server.resource.web.BearerTokenAuthenticationEntryPoint;
import org.springframework.security.web.AuthenticationEntryPoint;

/**
 * Wraps Spring's bearer-token entry point and appends the RFC 9728 §5.1
 * {@code resource_metadata} parameter to WWW-Authenticate, e.g.
 * {@code Bearer resource_metadata="https://pki-agent.ai-agent.id.eviden.internal:8445/.well-known/oauth-protected-resource"}.
 */
public class ResourceMetadataEntryPoint implements AuthenticationEntryPoint {

    private final String metadataUrl;
    private final BearerTokenAuthenticationEntryPoint delegate;

    public ResourceMetadataEntryPoint(String resourceId, BearerTokenAuthenticationEntryPoint delegate) {
        this.metadataUrl = resourceId + "/.well-known/oauth-protected-resource";
        this.delegate = delegate;
    }

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
                         AuthenticationException authException) throws IOException {
        delegate.commence(request, response, authException);
        String existing = response.getHeader("WWW-Authenticate");
        String prefix = (existing == null || existing.isBlank()) ? "Bearer" : existing;
        response.setHeader("WWW-Authenticate", prefix + " resource_metadata=\"" + metadataUrl + "\"");
    }
}
