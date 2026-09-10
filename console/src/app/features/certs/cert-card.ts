import { ChangeDetectionStrategy, Component, computed, input, output } from '@angular/core';

import { LiveCert } from '../../core/live';
import { CertDetail } from './cert-detail';

interface ChainRow {
  readonly sha256: string;
  readonly role: string;
  readonly name: string;
  readonly by: string;
  /** The one extension worth a line in the chain view: a name constraint. */
  readonly note: string | null;
}

function cn(dn: string): string {
  const match = /CN=([^,]+)/.exec(dn);
  return match === null ? dn : match[1];
}

function nameConstraint(c: LiveCert): string | null {
  const ext = c.details?.extensions.find((e) => e.name === 'Name Constraints');
  return ext === undefined ? null : ext.value;
}

/**
 * The one card every certificate on the page is shown in: a kicker naming
 * what and whose it is, one lead sentence, the openssl `x509 -text` view,
 * and behind disclosures the chain (one line per certificate) and the PEM.
 *
 * Which of those appear is decided by the caller, not by a mode flag: a
 * chain of one draws no chain disclosure, no PEM means no PEM section, no
 * download href means no download. The SVID cards carry no PEM on purpose
 * (P6's "metadata only" rule for /api/svid is unchanged); the issued
 * certificate carries it because that certificate is the artifact the human
 * asked for. There is never a key in here — none is ever issued out.
 */
@Component({
  selector: 'dc-cert-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertDetail],
  templateUrl: './cert-card.html',
  styleUrl: './cert-card.css',
})
export class CertCard {
  readonly kicker = input.required<string>();
  readonly lead = input.required<string>();
  readonly cert = input.required<LiveCert>();
  readonly chain = input<readonly LiveCert[]>([]);
  readonly pem = input<string | null>(null);
  readonly downloadHref = input<string | null>(null);
  readonly downloadName = input<string | null>(null);
  readonly reloadable = input(false);
  readonly reload = output<void>();

  protected readonly rows = computed<readonly ChainRow[]>(() =>
    this.chain().map((c) => ({
      sha256: c.sha256,
      role: c.role,
      name: cn(c.subject),
      by: c.subject === c.issuer ? 'self-signed' : `issued by ${cn(c.issuer)}`,
      note: nameConstraint(c),
    })),
  );
}
