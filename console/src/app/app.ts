import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';

import { SessionService } from './core/session';

/** P6.7: the app shell — top bar with the product identity and the session
 *  controls; pages render in the outlet. Session state loads once here. */
@Component({
  selector: 'dc-root',
  changeDetection: ChangeDetectionStrategy.OnPush,
  imports: [RouterLink, RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css',
})
export class App {
  protected readonly session = inject(SessionService);

  constructor() {
    void this.session.load();
  }

  protected logout(): void {
    void this.session.logout();
  }
}
