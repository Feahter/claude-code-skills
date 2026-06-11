# Memory Leak Debugging & Instrumentation

When you suspect a stream isn't being cleaned up, follow this process.

## Step 1 — Instrument with `finalize` to confirm teardown

```typescript
source$.pipe(
  finalize(() => console.warn('[LEAK-CHECK] stream torn down')),
  takeUntil(destroy$)
).subscribe();
// If you never see the log, the stream is leaking
```

`finalize` runs on complete, error, **and** unsubscribe — so it's the single most reliable signal that teardown happened.

## Step 2 — Match symptom to likely cause

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Subscription count grows on navigation | Missing `takeUntil` / `takeUntilDestroyed` | Add unsubscribe lifecycle |
| `shareReplay` keeps emitting after all unsub | `refCount: false` (default in older RxJS) | Use `{ refCount: true }` |
| WebSocket stays open | No `finalize` / `unsubscribe` on socket | Close in finalize or component destroy |
| Timer keeps firing | `interval()` / `timer()` without `take` / `takeUntil` | Bound the stream |
| Inner Observable never completes | `mergeMap` to long-lived inner stream | Use `switchMap`, or add `take` / `takeUntil` to inner |
| Subject never emits to late subscribers | Plain `Subject` doesn't replay | Switch to `ReplaySubject` or `BehaviorSubject` if last-value semantics are needed |

## Step 3 — Browser DevTools heap check

1. Chrome DevTools → Performance Monitor → JS Heap
2. Navigate away from the suspect component, trigger GC (trash can icon)
3. If heap doesn't drop back, take a heap snapshot and search for `Subscriber` / `Subject` objects
4. Inline subscription count probe:
   ```typescript
   source$.pipe(
     tap({
       subscribe: () => console.log('+sub'),
       unsubscribe: () => console.log('-sub')
     })
   )
   ```

## Reusable Debug Operators

Drop these into dev utilities; remove before production.

### `debug(label)` — log full lifecycle

```typescript
import { Observable, MonoTypeOperatorFunction } from 'rxjs';
import { tap } from 'rxjs/operators';

function debug<T>(label: string): MonoTypeOperatorFunction<T> {
  return tap({
    next: v => console.log(`[${label}] next:`, v),
    error: e => console.error(`[${label}] error:`, e),
    complete: () => console.log(`[${label}] complete`),
    subscribe: () => console.log(`[${label}] subscribed`),
    unsubscribe: () => console.log(`[${label}] unsubscribed`),
    finalize: () => console.log(`[${label}] finalized`)
  });
}
```

### `leakDetect(label)` — active subscription counter per label

```typescript
const activeSubs = new Map<string, number>();

function leakDetect<T>(label: string): MonoTypeOperatorFunction<T> {
  return (source: Observable<T>) => new Observable<T>(subscriber => {
    const count = (activeSubs.get(label) ?? 0) + 1;
    activeSubs.set(label, count);
    console.warn(`[LEAK-DETECT] ${label}: ${count} active subscriptions`);

    if (count > 5) {
      console.error(`[LEAK-DETECT] ${label}: possible leak! ${count} active subs`);
    }

    const sub = source.subscribe(subscriber);
    return () => {
      sub.unsubscribe();
      activeSubs.set(label, (activeSubs.get(label) ?? 1) - 1);
    };
  });
}
```

Usage:

```typescript
source$.pipe(debug('user-search'))
source$.pipe(leakDetect('user-search'))
```

Strip all `debug()` / `leakDetect()` calls before shipping. Use a proper logging library in production.

## ESLint Configuration

`eslint-plugin-rxjs` (Nicholas Jamieson) is no longer actively maintained. For existing projects it still works; for new Angular projects, `@angular-eslint` covers the most critical RxJS checks (nested subscribe, async pipe usage).

```json
{
  "extends": ["plugin:rxjs/recommended"],
  "rules": {
    "rxjs/no-nested-subscribe": "error",
    "rxjs/no-ignored-subscription": "error",
    "rxjs/no-unbound-methods": "error",
    "rxjs/no-unsafe-switchmap": "warn",
    "rxjs/no-subject-unsubscribe": "error",
    "rxjs/finnish": "warn"
  }
}
```
