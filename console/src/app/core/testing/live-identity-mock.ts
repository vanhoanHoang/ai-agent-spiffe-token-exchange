import { DemoToken } from '../demo-run';
import { LiveCert, LiveSvid } from '../live';

/** A self-signed root, shared by every chain the live fixtures draw. */
export const ROOT_CERT: LiveCert = {
  role: 'trust-anchor',
  subject: 'CN=Eviden Root CA,O=eviden',
  issuer: 'CN=Eviden Root CA,O=eviden',
  serial: '01',
  notBefore: '2026-01-01T00:00:00Z',
  notAfter: '2036-01-01T00:00:00Z',
  uriSans: [],
  sha256: 'cafe0123'.repeat(8),
};

/** The two live identity endpoints the certificate cards add — display
 *  only: decoded JWT-SVID claims with the signature redacted, and the chain
 *  the MCP server presented. Never a token, never a key. */
export function identityMock(): { jwtSvid: () => Promise<DemoToken>; peer: () => Promise<LiveSvid> } {
  return {
    jwtSvid: () =>
      Promise.resolve({
        name: 'JWT-SVID',
        description: 'The same workload, as a signed claim set.',
        header: { alg: 'ES256', typ: 'JWT', kid: '8f2c' },
        claims: {
          sub: 'spiffe://ai-agent.id.eviden.internal/agent-client',
          aud: ['http://keycloak:8080/realms/ai-agents'],
          exp: 1790000000,
        },
        signature: 'REDACTED',
      }),
    peer: () =>
      Promise.resolve({
        spiffeId: 'spiffe://ai-agent.id.eviden.internal/mcp-server',
        chain: [
          {
            role: 'leaf',
            subject: 'CN=mcp-server',
            issuer: 'CN=SPIRE Intermediate CA',
            serial: 'cd34',
            notBefore: '2026-07-31T10:00:00Z',
            notAfter: '2026-07-31T11:00:00Z',
            uriSans: ['spiffe://ai-agent.id.eviden.internal/mcp-server'],
            sha256: 'feedface'.repeat(8),
          },
          ROOT_CERT,
        ],
      }),
  };
}
