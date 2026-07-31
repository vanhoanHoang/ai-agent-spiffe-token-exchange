import { inject } from '@angular/core';
import { CanActivateFn, Router, Routes } from '@angular/router';

import { SessionService } from './core/session';
import { ConsolePage } from './pages/console/console-page';
import { LoginPage } from './pages/login/login-page';

/** Logged out (and not in guest mode) → the login page. Offline serving
 *  (file://, static host) has no /api/me and stays on the console rendering
 *  the recorded capture — the M11 exit is not behind the guard. */
export const consoleGuard: CanActivateFn = async () => {
  const session = inject(SessionService);
  const router = inject(Router);
  const state = await session.load();
  return state === 'anonymous' && !session.guest() ? router.parseUrl('/login') : true;
};

export const routes: Routes = [
  { path: 'login', component: LoginPage },
  { path: '', component: ConsolePage, canActivate: [consoleGuard] },
  { path: '**', redirectTo: '' },
];
