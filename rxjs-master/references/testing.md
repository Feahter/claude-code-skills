# RxJS Marble Testing

Use `TestScheduler` for deterministic time control. Virtual time lets you assert on time-based operators (`debounceTime`, `throttleTime`, `delay`, etc.) without real timeouts.

## Setup

```typescript
import { TestScheduler } from 'rxjs/testing';

describe('search stream', () => {
  let scheduler: TestScheduler;

  beforeEach(() => {
    scheduler = new TestScheduler((actual, expected) =>
      expect(actual).toEqual(expected)
    );
  });
});
```

## Basic Assertions

```typescript
it('should debounce and deduplicate input', () => {
  scheduler.run(({ cold, expectObservable }) => {
    //            frame: 0123456789...
    const input    = cold('a-b-c------|');
    const expected =       '------c----|';

    const result = input.pipe(
      debounceTime(3, scheduler),
      distinctUntilChanged()
    );

    expectObservable(result).toBe(expected);
  });
});
```

## Hot vs Cold Observables

```typescript
it('should switchMap and cancel previous', () => {
  scheduler.run(({ hot, cold, expectObservable }) => {
    const trigger = hot('--a------b------|');
    const inner1  = cold(  '---x|');
    const inner2  = cold(          '---y|');
    const expected =     '-----x------y---|';

    let i = 0;
    const result = trigger.pipe(
      switchMap(() => [inner1, inner2][i++])
    );

    expectObservable(result).toBe(expected);
  });
});
```

- `cold(...)` — observable that starts emitting on subscription (HTTP-style, each subscriber gets its own timeline)
- `hot(...)` — observable emitting independent of subscribers (DOM events, WebSocket)

## Marble Syntax Reference

| Char | Meaning |
|------|---------|
| `-` | 1 frame of time (default 10ms virtual) |
| `a-z`, `0-9` | Emitted value (mapped via values dict or used literally) |
| `|` | Complete |
| `#` | Error |
| `^` | Subscription point (hot only) |
| `!` | Unsubscription point |
| `()` | Synchronous group — all emissions on same frame |
| ` ` (space) | Ignored — use for alignment only |

## Passing Custom Values

```typescript
scheduler.run(({ cold, expectObservable }) => {
  const input    = cold('-a-b-c|', { a: 1, b: 2, c: 3 });
  const expected =      '-x-y-z|';
  const values   = { x: 2, y: 4, z: 6 };

  expectObservable(input.pipe(map(n => n * 2))).toBe(expected, values);
});
```

## Asserting Subscriptions

Verify when a source is (un)subscribed — useful for `takeUntil`, `switchMap` cancellation.

```typescript
scheduler.run(({ cold, hot, expectObservable, expectSubscriptions }) => {
  const source       = cold('-a-b-c-d|');
  const sub          =      '^---!    ';
  const notifier     = hot( '----t    ');
  const expected     =      '-a-b|    ';

  expectObservable(source.pipe(takeUntil(notifier))).toBe(expected);
  expectSubscriptions(source.subscriptions).toBe(sub);
});
```

## Common Pitfalls

- **Forgot to pass `scheduler` to time operators** — `debounceTime(300)` without the scheduler uses real time and ignores virtual clock. Always `debounceTime(300, scheduler)` in tests.
- **Space alignment only** — whitespace in marble strings is stripped; use dashes to align visually, but remember only non-space chars count as frames.
- **Forgot `|` on cold** — without complete, downstream operators like `takeUntil` may behave differently than expected.
- **Jest fake timers conflict** — disable `jest.useFakeTimers()` when using `TestScheduler`; they fight over the global clock.
