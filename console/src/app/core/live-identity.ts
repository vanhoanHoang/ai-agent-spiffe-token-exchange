import { Injectable } from '@angular/core';

import { DemoToken } from './demo-run';
import { LiveCert, LiveSvid } from './live';

/**
 * The two identity views the certificate cards add to live mode (same-origin
 * agent-web only, like {@link LiveClient}). Separate from LiveClient so the
 * P6 surface keeps its shape and its tests.
 *
 * Display only, and the security posture is the console's: the JWT-SVID
 * arrives as header + claims with the signature redacted — never the token —
 * and the peer chain is certificate metadata, never key or PEM material.
 */
@Injectable({ providedIn: 'root' })
export class LiveIdentityClient {
  /** The agent's JWT-SVID, decoded, in the shape the token card already
   *  renders. Null when not live. */
  async jwtSvid(): Promise<DemoToken | null> {
    try {
      const r = await fetch('/api/jwt-svid');
      if (!r.ok) {
        return null;
      }
      const d = (await r.json()) as {
        header?: unknown;
        claims?: unknown;
        signature?: unknown;
        description?: unknown;
      };
      if (!isRecord(d.header) || !isRecord(d.claims) || d.signature !== 'REDACTED') {
        return null;
      }
      return {
        name: 'JWT-SVID',
        description: typeof d.description === 'string' ? d.description : '',
        header: d.header,
        claims: d.claims,
        signature: 'REDACTED',
      };
    } catch {
      return null;
    }
  }

  /** The chain the named peer presented in a real mTLS handshake, accepted
   *  only because its SPIFFE ID is the one this agent expects. */
  async peer(target: 'mcp-server' | 'agent-pki'): Promise<LiveSvid | null> {
    try {
      const r = await fetch(`/api/peer?target=${target}`);
      if (!r.ok) {
        return null;
      }
      const d = (await r.json()) as { spiffeId?: unknown; chain?: unknown };
      if (typeof d.spiffeId !== 'string' || !Array.isArray(d.chain)) {
        return null;
      }
      return { spiffeId: d.spiffeId, chain: d.chain as LiveCert[] };
    } catch {
      return null;
    }
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}
