import { computed, inject, Injectable, signal } from '@angular/core';

import { LiveClient, LiveState, LiveUser } from './live';

/**
 * P6.7: one session truth for the routed app. Loaded once per page load;
 * the login-page/console guard and the shell top bar all read this signal.
 * `guest` marks "browse the recorded evidence without signing in" — the
 * M11 offline mode reached deliberately instead of by redirect accident.
 */
@Injectable({ providedIn: 'root' })
export class SessionService {
  private readonly live = inject(LiveClient);
  private loaded: Promise<LiveState> | null = null;

  readonly state = signal<LiveState | 'loading'>('loading');
  readonly guest = signal(false);
  readonly user = computed<LiveUser | null>(() => {
    const s = this.state();
    return typeof s === 'object' ? s : null;
  });

  load(): Promise<LiveState> {
    this.loaded ??= this.live.me().then((s) => {
      this.state.set(s);
      return s;
    });
    return this.loaded;
  }

  async logout(): Promise<void> {
    await this.live.logout();
    window.location.assign('/');
  }
}
