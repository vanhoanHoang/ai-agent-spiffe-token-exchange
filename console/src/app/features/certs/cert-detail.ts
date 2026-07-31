import { ChangeDetectionStrategy, Component, input } from '@angular/core';

import { LiveCert } from '../../core/live';

/** Full certificate breakdown in the openssl `x509 -text` layout PKI people
 *  read every day. Pure rendering of what /api/svid decoded. */
@Component({
  selector: 'dc-cert-detail',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './cert-detail.html',
  styleUrl: './cert-detail.css',
})
export class CertDetail {
  readonly cert = input.required<LiveCert>();
}
