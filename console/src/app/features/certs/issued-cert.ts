import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { IssuedCert, LiveCert } from '../../core/live';
import { CertCard } from './cert-card';

/**
 * The certificate the delegation chain produced (D-036) — the artifact the
 * whole two-hop story existed to make — in the same card as every other
 * certificate on the page, plus what only this one has: its PEM and a
 * download, because this certificate is what the human asked for.
 *
 * There is no private key to offer and that is the point, not a gap: the key
 * was generated inside the certificate service for the CSR and discarded at
 * issuance. What a human can take away is exactly what a certificate is —
 * public.
 */
@Component({
  selector: 'dc-issued-cert',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertCard],
  templateUrl: './issued-cert.html',
  styleUrl: './issued-cert.css',
})
export class IssuedCertPanel {
  readonly cert = input.required<IssuedCert>();

  protected readonly lead =
    'Signed by the corporate CA at the end of the chain. The private key was generated ' +
    'for the request and discarded at issuance — it never left the certificate service, ' +
    'so what you can take away is the certificate itself, which is public by design.';

  /** CN only — the filename the download will land under. */
  protected readonly commonName = computed(() => {
    const match = /CN=([^,]+)/.exec(this.cert().subject);
    return match ? match[1] : 'certificate';
  });

  protected readonly kicker = computed(() => `Issued certificate · ${this.commonName()}`);
  protected readonly fileName = computed(() => `${this.commonName()}.pem`);

  /** The chain as the service reported it; a lone certificate draws no chain. */
  protected readonly chain = computed<readonly LiveCert[]>(() => this.cert().chain ?? []);
}
