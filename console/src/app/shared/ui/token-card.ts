import { ChangeDetectionStrategy, Component, computed, input, signal } from '@angular/core';

import { DemoToken } from '../../core/demo-run';
import { IdentityRole } from '../../core/narrative';

interface ClaimRow {
  readonly k: string;
  readonly v: string;
  readonly role: IdentityRole | 'plain';
  readonly primary: boolean;
}

const PRIMARY = ['sub', 'preferred_username', 'act', 'aud', 'azp', 'scope'];

function roleOf(key: string): ClaimRow['role'] {
  if (key === 'sub' || key === 'preferred_username' || key === 'email') {
    return 'human';
  }
  if (key === 'act.sub') {
    return 'bridge';
  }
  if (key === 'aud' || key === 'azp' || key === 'scope') {
    return 'workload';
  }
  return 'plain';
}

function fmt(v: unknown): string {
  if (Array.isArray(v)) {
    return `[${v.join(', ')}]`;
  }
  if (v && typeof v === 'object') {
    return JSON.stringify(v).replace(/"/g, '');
  }
  return String(v);
}

@Component({
  selector: 'dc-token-card',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './token-card.html',
  styleUrl: './token-card.css',
})
export class TokenCard {
  readonly token = input.required<DemoToken>();
  readonly role = input.required<IdentityRole>();
  readonly kicker = input.required<string>();
  readonly title = input.required<string>();

  protected readonly expanded = signal(false);

  protected readonly header = computed(() => {
    const h = this.token().header;
    return `alg ${String(h['alg'] ?? '?')} · typ ${String(h['typ'] ?? 'JWT')}`;
  });

  protected readonly rows = computed<readonly ClaimRow[]>(() => {
    const rows = Object.entries(this.token().claims).map(([k, v]): ClaimRow => {
      if (k === 'act' && v && typeof v === 'object' && 'sub' in v) {
        return { k: 'act.sub', v: String((v as { sub: unknown }).sub), role: 'bridge', primary: true };
      }
      return { k, v: fmt(v), role: roleOf(k), primary: PRIMARY.includes(k) };
    });
    return this.expanded() ? rows : rows.filter((r) => r.primary);
  });

  protected toggle(): void {
    this.expanded.update((e) => !e);
  }
}
