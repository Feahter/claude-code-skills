---
name: rxjs-master
description: "RxJS / Observable 响应式编程专家。当用户在 TS/JS 代码里写、读、调、重构 RxJS 时触发，覆盖操作符选型、订阅管理与内存泄漏、错误处理与重试、marble 测试、性能调优、Promise 互转、Angular Signals 与 React hooks 互操作、响应式模式设计。只要代码出现 Observable / pipe / Subject 或用户提到响应式流 / reactive stream 就应触发，中英文请求均适用。不适用于纯 Promise / async-await 代码、RxJS 安装构建问题、一行玩具级问答。"
---

# RxJS Master

<!-- Methodology sources: Ben Lesh (RxJS lead), Andre Staltz (Cycle.js), Nicholas Jamieson (eslint-plugin-rxjs), Michael Hladky (rx-angular), Kwinten Pisman -->

## 8 Golden Rules

1. **Declarative first** — use operators, not imperative code in subscribe callbacks
2. **Always manage subscriptions** — takeUntil / async pipe / framework hooks / take(1)
3. **Never nest subscriptions** — flatten with higher-order operators
4. **Every stream needs error handling** — catchError inside inner Observable
5. **Share expensive work** — `shareReplay({ bufferSize: 1, refCount: true })`
6. **Type safety** — strict mode, no `any`, Finnish notation (`$` suffix)
7. **Test with marbles** — TestScheduler for deterministic time control
8. **Don't overuse RxJS** — single async value -> `firstValueFrom()` / Promise; complex streams -> Observable

## Operator Decision Tree

### Higher-Order (Flattening)

```
Need to flatten inner Observable?
+-- Cancel previous?        -> switchMap   (search, route navigation)
+-- Keep order?             -> concatMap   (file upload queue, sequential saves)
+-- Ignore new while busy?  -> exhaustMap  (login button, prevent double-submit)
+-- Run in parallel?        -> mergeMap    (batch requests, parallel downloads)
```

### Combination

```
Combine multiple Observables?
+-- All emit, use latest values  -> combineLatest
+-- All emit, pair by index      -> zip
+-- Any emits                    -> merge
+-- Sequential concatenation     -> concat
+-- First to emit wins           -> race
+-- Multicast with selector      -> connect  (RxJS 7.4+, replaces publish variants)
```

### Time Control

```
+-- Emit first in window    -> throttleTime  (scroll, resize)
+-- Emit last after silence  -> debounceTime  (search input, form validation)
+-- Sample at interval       -> sampleTime    (animation frames)
+-- Timeout                  -> timeout        (request deadline)
+-- Delay emission           -> delay          (UI transitions)
```

### Filtering

```
+-- By predicate      -> filter
+-- First N values    -> take(N)
+-- Until signal      -> takeUntil(notifier$)
+-- Skip duplicates   -> distinctUntilChanged  (use shallow compare, NOT JSON.stringify)
+-- First emission    -> first()
```

## Anti-Patterns (MUST AVOID)

### #1: Nested Subscriptions

```typescript
// BAD — Memory leak, inner sub never cleaned up
outer$.subscribe(x => {
  inner$.subscribe(y => { /* ... */ });
});

// GOOD — Flatten with higher-order operator
outer$.pipe(
  switchMap(x => inner$)
).subscribe(y => { /* ... */ });
```

### #2: Forgotten Unsubscribe

```typescript
// BAD — Leak, runs forever after component unmount
interval(1000).subscribe(console.log);

// GOOD — takeUntil pattern (classic Angular)
private destroy$ = new Subject<void>();

ngOnInit() {
  interval(1000).pipe(takeUntil(this.destroy$)).subscribe();
}
ngOnDestroy() {
  this.destroy$.next();
  this.destroy$.complete();
}

// BETTER — takeUntilDestroyed (Angular 16+, see Subscription Management)
```

### #3: Unhandled Error Killing Outer Stream

```typescript
// BAD — One API error terminates the entire click stream
clicks$.pipe(
  switchMap(() => api.getData())
).subscribe();

// GOOD — Catch inside inner Observable, outer stream survives
clicks$.pipe(
  switchMap(() => api.getData().pipe(
    catchError(err => of(null))
  ))
).subscribe();
```

### #4: Subject Overuse

```typescript
// BAD — Unnecessary Subject, just wrapping an operator
const subject = new Subject<number>();
source$.subscribe(x => subject.next(x * 2));

// GOOD — Use operator chain directly
const result$ = source$.pipe(map(x => x * 2));
```

Subject is valid only for: bridging non-reactive APIs, multicasting imperative events, state containers (BehaviorSubject).

### #5: Observable in Hot Path

```typescript
// BAD — Creating Observable for sync computation
function double(n: number) {
  return firstValueFrom(of(n).pipe(map(x => x * 2)));
}

// GOOD — Plain function for sync work
function double(n: number) { return n * 2; }
```

### #6: Using deprecated toPromise()

```typescript
// BAD — toPromise is deprecated since RxJS 7, removed in 8
const value = await source$.toPromise();

// GOOD — firstValueFrom for first emission
const first = await firstValueFrom(source$);

// GOOD — lastValueFrom for last emission (waits for complete)
const last = await lastValueFrom(source$);

// GOOD — with default value to avoid EmptyError
const safe = await firstValueFrom(source$, { defaultValue: null });
```

The key difference: `firstValueFrom` resolves on the first emission, `lastValueFrom` waits for the Observable to complete and resolves with the last value. Both throw `EmptyError` if the Observable completes without emitting (unless a `defaultValue` is provided).

## Error Handling: 3-Layer Defense

### Layer 1 — Local Catch (inside switchMap)

```typescript
outer$.pipe(
  switchMap(val => riskyCall(val).pipe(
    catchError(err => of(fallbackValue)) // outer stream unaffected
  ))
)
```

### Layer 2 — Retry with Exponential Backoff

```typescript
source$.pipe(
  retry({
    count: 3,
    delay: (err, retryCount) => timer(Math.pow(2, retryCount) * 1000)
  })
)
```

### Layer 3 — Global Notification

```typescript
source$.pipe(
  catchError(err => {
    errorTracker.report(err);
    notifyUser('Operation failed');
    return EMPTY;
  })
)
```

**Rule**: Always catch at Layer 1 first. Layer 2 for transient failures. Layer 3 as last resort.

## Custom Operators

Writing reusable operators is essential for DRY reactive code. Two approaches depending on complexity:

### Composition (preferred for most cases)

Combine existing operators using the standalone `pipe()` function. This is simpler and less error-prone because existing operators handle subscription lifecycle correctly.

```typescript
import { pipe, OperatorFunction } from 'rxjs';
import { filter, map } from 'rxjs/operators';

// MonoTypeOperatorFunction<T> when input/output types are the same
function filterNil<T>(): MonoTypeOperatorFunction<T> {
  return filter((v): v is NonNullable<T> => v != null);
}

// OperatorFunction<T, R> when types differ
function mapToProperty<T, K extends keyof T>(key: K): OperatorFunction<T, T[K]> {
  return map(obj => obj[key]);
}

// Composing multiple operators
function searchPipeline<T>(debounceMs = 300): OperatorFunction<string, string> {
  return pipe(
    debounceTime(debounceMs),
    distinctUntilChanged(),
    filter(q => q.length >= 2)
  );
}

// Usage
input$.pipe(searchPipeline(500)).subscribe();
```

### Manual (when you need full control over subscription)

Create operators from scratch when you need custom subscription logic (e.g., custom buffering, stateful transforms). Always handle subscriber teardown to avoid leaks.

```typescript
import { Observable, OperatorFunction } from 'rxjs';

function tapOnce<T>(fn: (value: T) => void): MonoTypeOperatorFunction<T> {
  return (source: Observable<T>) =>
    new Observable<T>(subscriber => {
      let first = true;
      const sub = source.subscribe({
        next(value) {
          if (first) { fn(value); first = false; }
          subscriber.next(value);
        },
        error(err) { subscriber.error(err); },
        complete() { subscriber.complete(); }
      });
      // Always return teardown logic
      return () => sub.unsubscribe();
    });
}
```

## Performance Checklist

- [ ] `shareReplay({ bufferSize: 1, refCount: true })` for shared HTTP calls
- [ ] `throttleTime(16)` for scroll/mouse/resize events (~60fps)
- [ ] `debounceTime(300)` for user text input
- [ ] `animationFrameScheduler` for DOM update synchronization
- [ ] `bufferTime(100, null, 50)` for batch processing high-frequency events
- [ ] `distinctUntilChanged((a, b) => a.id === b.id)` — shallow compare, never JSON.stringify
- [ ] Virtual scrolling for lists >500 items
- [ ] `share()` for side-effect streams that don't need replay
- [ ] Prefer `connect()` over deprecated `publish()`/`multicast()`/`refCount()` chains

## Marble Testing

Use `TestScheduler` for deterministic virtual time. Core syntax: `-` = 1 frame, `a-z` / `0-9` = values, `|` = complete, `#` = error, `^` = subscription, `!` = unsubscribe, `()` = sync group.

Pass the scheduler to time operators (`debounceTime(300, scheduler)`), otherwise they use real time and ignore virtual clock.

For full examples (hot vs cold, subscription assertions, custom value dicts, common pitfalls), see [references/testing.md](references/testing.md).

## Thinking Reactively (Staltz Method)

When designing a reactive feature, follow these 4 steps:

1. **Identify all input streams** — DOM events, HTTP responses, WebSocket messages, timers
2. **Define each stream's meaning** — transform raw events into domain data via operators
3. **Combine streams to produce output** — use combineLatest/merge/switchMap to derive final state
4. **Handle edge cases** — loading states, errors, empty states, race conditions

## Subscription Management Quick Reference

| Context | Method |
|---------|--------|
| Angular template | `async` pipe |
| Angular 16+ component | `takeUntilDestroyed()` from `@angular/core/rxjs-interop` |
| Angular legacy component | `takeUntil(destroy$)` + `ngOnDestroy` |
| Angular -> Signals | `toSignal(obs$)` / `toObservable(signal)` |
| React hooks | `useEffect` cleanup + custom `useObservable` hook |
| One-shot request | `take(1)` or `firstValueFrom()` |
| Manual | `Subscription.add()` + `unsubscribe()` |

### Angular Signals Interop (16+) / React Hooks

Angular's `@angular/core/rxjs-interop` (`toSignal`, `toObservable`, `takeUntilDestroyed`) lets you adopt Signals without rewriting Observable-based code. React's equivalent is a custom `useObservable` hook backed by `useEffect` cleanup.

Rule of thumb: bridge at the edges only — don't bounce repeatedly between Signal / Observable / React state in the same pipeline.

For full code (both `toSignal` / `toObservable` patterns, `useObservable` + `useEventObservable` hooks, identity / memoization gotchas), see [references/framework-interop.md](references/framework-interop.md).

## Memory Leak Debugging

Three-step process: instrument with `finalize` to confirm teardown → match symptom to common cause → confirm via DevTools heap snapshot.

Quickest probe:
```typescript
source$.pipe(
  finalize(() => console.warn('[LEAK-CHECK] stream torn down')),
  takeUntil(destroy$)
).subscribe();
// If you never see the log, the stream is leaking
```

For the full symptom-cause table, reusable `debug()` / `leakDetect()` operators, DevTools heap workflow, and ESLint config (`eslint-plugin-rxjs`, `@angular-eslint`), see [references/debugging.md](references/debugging.md).

## Production Patterns

Detailed code examples for 12 production-ready patterns:

- See [references/patterns.md](references/patterns.md) for complete implementations:
  1. Search autocomplete
  2. Infinite scroll
  3. WebSocket auto-reconnect
  4. Multi-field form validation
  5. Drag and drop
  6. State container (BehaviorSubject)
  7. Redux-like store (scan + actions)
  8. Retry with exponential backoff
  9. Request deduplication cache
  10. Virtual scroll controller
  11. Smart polling
  12. Batch processor
