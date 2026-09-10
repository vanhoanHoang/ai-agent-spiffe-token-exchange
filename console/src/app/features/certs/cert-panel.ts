import {
  ChangeDetectionStrategy,
  Component,
  computed,
  DestroyRef,
  inject,
  input,
  output,
  signal,
} from '@angular/core';

import { DemoToken } from '../../core/demo-run';
import { LiveSvid } from '../../core/live';
import { TokenCard } from '../../shared/ui/token-card';
import { CertCard } from './cert-card';
import { countdown, rotationView } from './rotation';

function cn(dn: string): string {
  const match = /CN=([^,]+)/.exec(dn);
  return match === null ? dn : match[1];
}

/** The workload's two proofs, under the step that fetches them: the CURRENT
 *  X.509-SVID as a certificate card (chain behind a disclosure, live countdown
 *  to the leaf's estimated rotation in the lead) and the JWT-SVID as decoded
 *  claims in the token card — the same SPIFFE ID in both, never a token.
 *  When the rotation estimate comes due the panel re-fetches on its own until
 *  the new leaf appears, so rotation shows up without anyone touching the page. */
@Component({
  selector: 'dc-cert-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertCard, TokenCard],
  templateUrl: './cert-panel.html',
  styleUrl: './cert-panel.css',
})
export class CertPanel {
  readonly svid = input.required<LiveSvid>();
  readonly jwt = input<DemoToken | null>(null);
  readonly reload = output<void>();

  private readonly now = signal(Date.now());
  private lastAutoReload = 0;

  constructor() {
    const timer = setInterval(() => this.tick(), 1000);
    inject(DestroyRef).onDestroy(() => clearInterval(timer));
  }

  protected readonly leaf = computed(
    () => this.svid().chain.find((c) => c.role === 'leaf') ?? this.svid().chain[0],
  );

  protected readonly kicker = computed(() => {
    const l = this.leaf();
    return `X.509-SVID · ${l === undefined ? 'workload' : cn(l.subject)}`;
  });

  protected readonly lead = computed(() => {
    const l = this.leaf();
    const who = `Minted by SPIRE for ${this.svid().spiffeId}.`;
    if (l === undefined) {
      return who;
    }
    const v = rotationView(this.now(), l.notBefore, l.notAfter);
    return (
      `${who} Expires in ${countdown(v.expiresInMs)}, rotation expected in about ` +
      `${countdown(v.rotationInMs)} (SPIRE renews at half the TTL); the SPIFFE ID never changes.`
    );
  });

  /** Once the estimated rotation is due, re-fetch every 30s; the new leaf's
   *  half-life resets the countdown and the polling stops by itself. */
  private tick(): void {
    this.now.set(Date.now());
    const l = this.leaf();
    if (l === undefined) {
      return;
    }
    const due = rotationView(this.now(), l.notBefore, l.notAfter).rotationInMs <= 0;
    if (due && this.now() - this.lastAutoReload > 30_000) {
      this.lastAutoReload = this.now();
      this.reload.emit();
    }
  }
}
