import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

import { IssuedCert } from '../../core/live';
import { CertDetail } from './cert-detail';

/**
 * The certificate the delegation chain produced (D-036) — the artifact the
 * whole two-hop story existed to make. Rendered in the same openssl `x509
 * -text` layout as the agent's own SVID, and downloadable as PEM.
 *
 * There is no private key to offer and that is the point, not a gap: the key
 * was generated inside the certificate service for the CSR and discarded at
 * issuance. What a human can take away is exactly what a certificate is —
 * public.
 */
@Component({
  selector: 'dc-issued-cert',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertDetail],
  templateUrl: './issued-cert.html',
  styleUrl: './issued-cert.css',
})
export class IssuedCertPanel {
  readonly cert = input.required<IssuedCert>();

  /** CN only — the filename the download will land under. */
  protected readonly commonName = computed(() => {
    const match = /CN=([^,]+)/.exec(this.cert().subject);
    return match ? match[1] : 'certificate';
  });
}
