import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { LiveSvid } from '../../core/live';
import { CertCard } from './cert-card';

function cn(dn: string): string {
  const match = /CN=([^,]+)/.exec(dn);
  return match === null ? dn : match[1];
}

/** The other side of the mTLS handshake: the certificate chain the server
 *  presented, under the step that makes the call. It is on the page only
 *  because a real handshake with the accept-only-this-SPIFFE-ID context
 *  succeeded — the same check the agent's calls apply. Metadata only. */
@Component({
  selector: 'dc-peer-cert',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertCard],
  templateUrl: './peer-cert.html',
  styleUrl: './peer-cert.css',
})
export class PeerCert {
  readonly peer = input.required<LiveSvid>();

  protected readonly leaf = computed(
    () => this.peer().chain.find((c) => c.role === 'leaf') ?? this.peer().chain[0],
  );

  protected readonly kicker = computed(() => {
    const l = this.leaf();
    return `Server certificate · ${l === undefined ? 'peer' : cn(l.subject)}`;
  });

  protected readonly lead = computed(
    () =>
      `What ${this.peer().spiffeId} presented in the handshake. Accepted because its ` +
      'SPIFFE ID is the one this agent expects, verified against the SPIFFE bundle — ' +
      'not the system trust store.',
  );
}
