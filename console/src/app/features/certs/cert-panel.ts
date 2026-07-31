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

import { LiveSvid } from '../../core/live';
import { CertDetail } from './cert-detail';
import { countdown, rotationView } from './rotation';

/** The agent's CURRENT X.509-SVID chain, straight from the Workload API via
 *  /api/svid — with an expert expander per certificate and a live countdown
 *  to the leaf's estimated rotation (SPIRE renews at ~half TTL). When the
 *  estimate comes due, the panel re-fetches on its own until the new leaf
 *  appears — rotation shows up without anyone touching the page. */
@Component({
  selector: 'dc-cert-panel',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [CertDetail],
  templateUrl: './cert-panel.html',
  styleUrl: './cert-panel.css',
})
export class CertPanel {
  readonly svid = input.required<LiveSvid>();
  readonly reload = output<void>();

  protected readonly expanded = signal<string | null>(null);
  private readonly now = signal(Date.now());
  private lastAutoReload = 0;

  constructor() {
    const timer = setInterval(() => this.tick(), 1000);
    inject(DestroyRef).onDestroy(() => clearInterval(timer));
  }

  protected readonly leaf = computed(() =>
    this.svid().chain.find((c) => c.role === 'leaf'),
  );

  protected readonly rotation = computed(() => {
    const l = this.leaf();
    if (l === undefined) {
      return null;
    }
    const v = rotationView(this.now(), l.notBefore, l.notAfter);
    return { expires: countdown(v.expiresInMs), rotates: countdown(v.rotationInMs) };
  });

  protected toggle(sha: string): void {
    this.expanded.update((cur) => (cur === sha ? null : sha));
  }

  protected cn(dn: string): string {
    const match = /CN=([^,]+)/.exec(dn);
    return match === null ? dn : match[1];
  }

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
