import { ChangeDetectionStrategy, Component, input, output } from '@angular/core';

import { LiveSvid } from '../../core/live';

/** The agent's CURRENT X.509-SVID chain, straight from the Workload API via
 *  /api/svid — subjects, serials, validity windows, URI SANs, fingerprints.
 *  Reloading shows SPIRE's rotation: the leaf serial and validity change. */
@Component({
  selector: 'dc-cert-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './cert-panel.html',
  styleUrl: './cert-panel.css',
})
export class CertPanel {
  readonly svid = input.required<LiveSvid>();
  readonly reload = output<void>();

  protected cn(dn: string): string {
    const match = /CN=([^,]+)/.exec(dn);
    return match === null ? dn : match[1];
  }

  protected short(hex: string): string {
    return hex.length > 16 ? `${hex.slice(0, 16)}…` : hex;
  }
}
