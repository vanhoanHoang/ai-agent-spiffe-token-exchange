import { TestBed } from '@angular/core/testing';

import { demoRunFixture } from '../../core/testing/fixture';
import { LogPanel } from './log-panel';

describe('LogPanel', () => {
  async function render() {
    await TestBed.configureTestingModule({ imports: [LogPanel] }).compileComponents();
    const fixture = TestBed.createComponent(LogPanel);
    fixture.componentRef.setInput('lines', demoRunFixture().log_tail);
    await fixture.whenStable();
    return fixture;
  }

  it('replays: starts partial, advances line by line', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelectorAll('.line').length).toBe(2);
    el.querySelector<HTMLButtonElement>('.ctl')?.click();
    await fixture.whenStable();
    expect(el.querySelectorAll('.line').length).toBe(3);
  });

  it('colorizes identity tokens and denials', async () => {
    const fixture = await render();
    const el = fixture.nativeElement as HTMLElement;
    Array.from(el.querySelectorAll<HTMLButtonElement>('.ctl'))
      .find((b) => b.textContent?.includes('Show all'))
      ?.click();
    await fixture.whenStable();
    expect(el.querySelector('.tok.sub')).toBeTruthy();
    expect(el.querySelector('.tok.act')).toBeTruthy();
    expect(el.querySelector('.tok.reject')).toBeTruthy();
  });
});
