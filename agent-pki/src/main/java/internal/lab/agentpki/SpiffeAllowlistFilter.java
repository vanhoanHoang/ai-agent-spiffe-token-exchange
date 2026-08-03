package internal.lab.agentpki;

import java.io.IOException;
import java.security.cert.CertificateParsingException;
import java.security.cert.X509Certificate;
import java.util.Collection;
import java.util.List;
import java.util.Set;

import java.util.Map;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Second half of the D-006 enforcement split: the TLS handshake already proved
 * the peer holds a valid ai-agent.id.eviden.internal SVID; this filter enforces WHICH workloads
 * may call (allowlist) and answers 403 otherwise — the M5/M9 "unlisted SPIFFE
 * ID" semantics. SPIFFE ID != user authorization: this gate only says which
 * workload may present tokens here, never what the human may do.
 */
@Component
public class SpiffeAllowlistFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(SpiffeAllowlistFilter.class);
    private static final int URI_SAN = 6;
    private static final String PEER_CERTS_ATTR = "jakarta.servlet.request.X509Certificate";

    private final Set<String> allowlist;
    private final AuditLogBuffer auditLog;

    public SpiffeAllowlistFilter(@Value("${pki.allowed-spiffe-ids}") String allowedSpiffeIds,
            AuditLogBuffer auditLog) {
        this.allowlist = Set.copyOf(List.of(allowedSpiffeIds.split("\\s*,\\s*")));
        this.auditLog = auditLog;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        if (request.getRequestURI().startsWith("/.well-known/")) {
            chain.doFilter(request, response);
            return;
        }
        String peerSpiffeId = peerSpiffeId(request);
        if (peerSpiffeId == null) {
            deny(response, "no SPIFFE ID in client certificate");
            return;
        }
        if (!allowlist.contains(peerSpiffeId)) {
            log.warn("rejecting non-allowlisted workload {}", peerSpiffeId);
            deny(response, "workload not allowlisted");
            return;
        }
        // D-009 (M8 replacement): if the token asserts an actor, the caller MUST
        // be that actor — issuance-time proof (JWT-SVID client auth -> act.sub)
        // chained to call-time proof (X509-SVID key possession -> peer identity).
        // Runs after the security chain (Boot registers this filter at lowest
        // precedence), so the validated JWT is in the SecurityContext here.
        String actSub = actorSub();
        if (actSub != null && !actSub.equals(peerSpiffeId)) {
            log.warn("rejecting token replay: act.sub={} but peer={}", actSub, peerSpiffeId);
            deny(response, "actor/peer mismatch");
            return;
        }
        request.setAttribute("pki.peer.spiffeId", peerSpiffeId);
        auditLog.record("%s %s allowed sub=%s act=%s peer=%s".formatted(
                request.getMethod(), request.getRequestURI(), subjectOrAnon(), actSub, peerSpiffeId));
        chain.doFilter(request, response);
    }

    private String subjectOrAnon() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        return (auth instanceof JwtAuthenticationToken jwtAuth) ? jwtAuth.getToken().getSubject() : "anonymous";
    }

    private String actorSub() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth instanceof JwtAuthenticationToken jwtAuth
                && jwtAuth.getToken().getClaim("act") instanceof Map<?, ?> act
                && act.get("sub") instanceof String sub) {
            return sub;
        }
        return null;
    }

    private String peerSpiffeId(HttpServletRequest request) {
        Object attr = request.getAttribute(PEER_CERTS_ATTR);
        if (!(attr instanceof X509Certificate[] certs) || certs.length == 0) {
            return null;
        }
        try {
            Collection<List<?>> sans = certs[0].getSubjectAlternativeNames();
            if (sans == null) {
                return null;
            }
            for (List<?> san : sans) {
                if (san.size() >= 2 && Integer.valueOf(URI_SAN).equals(san.get(0))
                        && san.get(1) instanceof String uri && uri.startsWith("spiffe://")) {
                    return uri;
                }
            }
            return null;
        } catch (CertificateParsingException e) {
            // fail closed: unparseable peer certificate is not an allowlisted peer
            return null;
        }
    }

    private void deny(HttpServletResponse response, String reason) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.getWriter().write("{\"error\":\"forbidden\",\"error_description\":\"" + reason + "\"}");
    }
}
