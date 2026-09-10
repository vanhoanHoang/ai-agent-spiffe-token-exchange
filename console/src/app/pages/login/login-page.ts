import { ChangeDetectionStrategy, Component, effect, inject } from '@angular/core';
import { Router } from '@angular/router';

import { SessionService } from '../../core/session';

/** P6.7: the sign-in landing page. Live mode (served by agent-web) offers one
 *  identity-only sign-in (M15: task authority is requested at the point of
 *  use, so the audit-scope variant is off the front door for now); already
 *  signed-in visitors are sent straight to the console; offline serving
 *  explains itself and offers the recorded evidence as the only way in. */
@Component({
  selector: 'dc-login-page',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './login-page.html',
  styleUrl: './login-page.css',
})
export class LoginPage {
  protected readonly session = inject(SessionService);
  private readonly router = inject(Router);

  constructor() {
    void this.session.load();
    effect(() => {
      if (this.session.user() !== null) {
        void this.router.navigateByUrl('/');
      }
    });
  }

  protected browse(): void {
    this.session.guest.set(true);
    void this.router.navigateByUrl('/');
  }
}
