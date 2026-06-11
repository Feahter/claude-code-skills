# RxJS Production Patterns

## Table of Contents

1. [Search Autocomplete](#1-search-autocomplete)
2. [Infinite Scroll](#2-infinite-scroll)
3. [WebSocket Auto-Reconnect](#3-websocket-auto-reconnect)
4. [Multi-Field Form Validation](#4-multi-field-form-validation)
5. [Drag and Drop](#5-drag-and-drop)
6. [State Container](#6-state-container)
7. [Redux-like Store](#7-redux-like-store)
8. [Retry with Exponential Backoff](#8-retry-with-exponential-backoff)
9. [Request Deduplication Cache](#9-request-deduplication-cache)
10. [Virtual Scroll Controller](#10-virtual-scroll-controller)
11. [Smart Polling](#11-smart-polling)
12. [Batch Processor](#12-batch-processor)

---

## 1. Search Autocomplete

Operators: `debounceTime` + `distinctUntilChanged` + `filter` + `switchMap` + `catchError`

```typescript
import { fromEvent, of, BehaviorSubject } from 'rxjs';
import {
  debounceTime, distinctUntilChanged, switchMap,
  map, filter, catchError, tap, startWith
} from 'rxjs/operators';

function createSearch(input: HTMLInputElement, api: { search(q: string): Observable<any[]> }) {
  const loading$ = new BehaviorSubject(false);
  const error$ = new BehaviorSubject<string | null>(null);

  const results$ = fromEvent(input, 'input').pipe(
    map(e => (e.target as HTMLInputElement).value.trim()),
    debounceTime(300),
    distinctUntilChanged(),
    filter(q => q.length >= 2),
    tap(() => { loading$.next(true); error$.next(null); }),
    switchMap(q => api.search(q).pipe(
      tap(() => loading$.next(false)),
      catchError(err => {
        loading$.next(false);
        error$.next(err.message);
        return of([]);
      })
    )),
    startWith([])
  );

  return { results$, loading$: loading$.asObservable(), error$: error$.asObservable() };
}
```

**Key points**: `switchMap` cancels previous in-flight requests. `catchError` inside prevents stream death.

---

## 2. Infinite Scroll

Operators: `fromEvent` + `throttleTime` + `scan` + `switchMap` + `shareReplay`

```typescript
function createInfiniteScroll<T>(
  container: HTMLElement,
  loadPage: (page: number) => Observable<{ items: T[]; hasMore: boolean }>
) {
  const loading$ = new BehaviorSubject(false);

  const items$ = fromEvent(container, 'scroll').pipe(
    throttleTime(200),
    filter(() => {
      const { scrollTop, scrollHeight, clientHeight } = container;
      return scrollHeight - scrollTop - clientHeight < 100 && !loading$.value;
    }),
    startWith(null), // trigger initial load
    scan(page => page + 1, 0),
    tap(() => loading$.next(true)),
    concatMap(page => loadPage(page).pipe(  // concatMap preserves order
      tap(() => loading$.next(false)),
      catchError(() => { loading$.next(false); return of({ items: [], hasMore: false }); })
    )),
    takeWhile(result => result.hasMore, true),
    scan((all: T[], result) => [...all, ...result.items], []),
    shareReplay({ bufferSize: 1, refCount: true })
  );

  return { items$, loading$: loading$.asObservable() };
}
```

**Key points**: `concatMap` (not switchMap) to preserve page ordering. `scan` accumulates items.

---

## 3. WebSocket Auto-Reconnect

Operators: `webSocket` + `retry` + `delay` + `tap`

```typescript
import { webSocket } from 'rxjs/webSocket';
import { retry, tap, delay, BehaviorSubject, timer } from 'rxjs';

function createRealtimeConnection<T>(url: string, maxRetries = 5) {
  const connected$ = new BehaviorSubject(false);
  let retryCount = 0;

  const socket$ = webSocket<T>({
    url,
    openObserver: { next: () => { connected$.next(true); retryCount = 0; } },
    closeObserver: { next: () => connected$.next(false) }
  });

  const messages$ = socket$.pipe(
    tap({ error: () => connected$.next(false) }),
    retry({
      count: maxRetries,
      delay: (err, attempt) => {
        const backoff = Math.min(1000 * Math.pow(2, attempt), 30000);
        return timer(backoff);
      }
    })
  );

  return {
    messages$,
    connected$: connected$.asObservable(),
    send: (msg: T) => socket$.next(msg),
    close: () => socket$.complete()
  };
}
```

**Key points**: Exponential backoff on reconnect. `connected$` tracks connection state.

---

## 4. Multi-Field Form Validation

Operators: `combineLatest` + `debounceTime` + `switchMap` (async validation)

```typescript
interface ValidationResult {
  valid: boolean;
  errors: string[];
}

function createFormValidator(form: HTMLFormElement, api: { checkEmail(e: string): Observable<boolean> }) {
  const field$ = (name: string) => fromEvent(
    form.querySelector(`[name="${name}"]`) as HTMLInputElement, 'input'
  ).pipe(
    map(e => (e.target as HTMLInputElement).value),
    debounceTime(300),
    distinctUntilChanged(),
    startWith('')
  );

  const email$ = field$('email');
  const password$ = field$('password');

  // Local + async email validation
  const emailValid$ = email$.pipe(
    switchMap(emailValue => {
      const localValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailValue);
      if (!localValid) {
        return of({ valid: false, errors: ['Invalid email format'] });
      }
      return api.checkEmail(emailValue).pipe(
        map(available => ({ valid: available, errors: available ? [] : ['Email taken'] })),
        catchError(() => of({ valid: false, errors: ['Validation failed'] }))
      );
    }),
    startWith({ valid: false, errors: [] } as ValidationResult)
  );

  // Local password validation
  const passwordValid$ = password$.pipe(
    map(p => {
      const errors: string[] = [];
      if (p.length < 8) errors.push('Min 8 characters');
      if (!/[A-Z]/.test(p)) errors.push('Need uppercase');
      if (!/[0-9]/.test(p)) errors.push('Need number');
      return { valid: errors.length === 0, errors };
    }),
    startWith({ valid: false, errors: [] } as ValidationResult)
  );

  const formValid$ = combineLatest({ email: emailValid$, password: passwordValid$ }).pipe(
    map(v => Object.values(v).every(r => r.valid))
  );

  return { emailValid$, passwordValid$, formValid$ };
}
```

---

## 5. Drag and Drop

Operators: `mousedown` → `switchMap(mousemove)` → `takeUntil(mouseup)`

```typescript
function makeDraggable(element: HTMLElement) {
  const mouseDown$ = fromEvent<MouseEvent>(element, 'mousedown');
  const mouseMove$ = fromEvent<MouseEvent>(document, 'mousemove');
  const mouseUp$ = fromEvent<MouseEvent>(document, 'mouseup');

  return mouseDown$.pipe(
    tap(e => e.preventDefault()),
    switchMap(start => mouseMove$.pipe(
      map(move => ({
        x: move.clientX - start.clientX,
        y: move.clientY - start.clientY
      })),
      takeUntil(mouseUp$)
    ))
  );
  // Usage: drag$.subscribe(({ x, y }) => el.style.transform = `translate(${x}px, ${y}px)`);
}
```

**Key points**: `switchMap` auto-cleans previous drag session. `takeUntil(mouseUp$)` ends each drag.

---

## 6. State Container

BehaviorSubject-based store with selectors.

```typescript
class Store<T extends Record<string, any>> {
  private state$: BehaviorSubject<T>;

  constructor(initial: T) {
    this.state$ = new BehaviorSubject(initial);
  }

  get snapshot(): T { return this.state$.value; }
  get state(): Observable<T> { return this.state$.asObservable(); }

  select<K extends keyof T>(key: K): Observable<T[K]> {
    return this.state$.pipe(
      map(s => s[key]),
      distinctUntilChanged()
    );
  }

  setState(partial: Partial<T>): void {
    this.state$.next({ ...this.snapshot, ...partial });
  }

  update(fn: (state: T) => T): void {
    this.state$.next(fn(this.snapshot));
  }
}

// Usage
const store = new Store({ user: null, theme: 'dark', loading: false });
store.select('theme').subscribe(theme => applyTheme(theme));
store.setState({ loading: true });
```

---

## 7. Redux-like Store

Subject + scan for action/reducer pattern.

```typescript
type Reducer<S, A> = (state: S, action: A) => S;

class ReduxStore<S, A extends { type: string }> {
  private actions$ = new Subject<A>();
  readonly state$: Observable<S>;

  constructor(initial: S, reducer: Reducer<S, A>) {
    this.state$ = this.actions$.pipe(
      scan((state, action) => reducer(state, action), initial),
      startWith(initial),
      shareReplay(1)
    );
  }

  dispatch(action: A): void { this.actions$.next(action); }

  select<R>(selector: (state: S) => R): Observable<R> {
    return this.state$.pipe(map(selector), distinctUntilChanged());
  }
}

// Usage
interface State { count: number }
type Action = { type: 'INC' } | { type: 'DEC' } | { type: 'SET'; payload: number };

const store = new ReduxStore<State, Action>({ count: 0 }, (state, action) => {
  switch (action.type) {
    case 'INC': return { count: state.count + 1 };
    case 'DEC': return { count: state.count - 1 };
    case 'SET': return { count: action.payload };
    default: return state;
  }
});

store.dispatch({ type: 'INC' });
```

---

## 8. Retry with Exponential Backoff

Reusable custom operator.

```typescript
function retryWithBackoff<T>(maxRetries = 3, initialDelay = 1000, maxDelay = 30000) {
  return (source: Observable<T>) => source.pipe(
    retry({
      count: maxRetries,
      delay: (error, retryCount) => {
        const delay = Math.min(initialDelay * Math.pow(2, retryCount - 1), maxDelay);
        return timer(delay);
      }
    })
  );
}

// Usage
api.getData().pipe(
  retryWithBackoff(3, 1000, 10000),
  catchError(err => { notify('All retries failed'); return of(null); })
).subscribe();
```

---

## 9. Request Deduplication Cache

Prevent duplicate in-flight requests.

```typescript
const inFlight = new Map<string, Observable<any>>();

function dedupedRequest<T>(key: string, factory: () => Observable<T>): Observable<T> {
  if (!inFlight.has(key)) {
    const shared = factory().pipe(
      shareReplay(1),
      finalize(() => inFlight.delete(key))
    );
    inFlight.set(key, shared);
  }
  return inFlight.get(key)!;
}

// Usage — same key returns same in-flight Observable
const user$ = dedupedRequest('user-123', () => api.getUser('123'));
```

---

## 10. Virtual Scroll Controller

Render only visible items from large dataset.

```typescript
function createVirtualScroll<T>(container: HTMLElement, items: T[], itemHeight = 50) {
  const visibleCount = Math.ceil(container.clientHeight / itemHeight) + 2; // buffer

  return fromEvent(container, 'scroll').pipe(
    throttleTime(16), // ~60fps
    map(() => container.scrollTop),
    map(scrollTop => {
      const start = Math.floor(scrollTop / itemHeight);
      const end = Math.min(start + visibleCount, items.length);
      return { start, end, visible: items.slice(start, end), offsetY: start * itemHeight };
    }),
    distinctUntilChanged((a, b) => a.start === b.start),
    startWith({ start: 0, end: visibleCount, visible: items.slice(0, visibleCount), offsetY: 0 })
  );
}
```

---

## 11. Smart Polling

Configurable polling with pause/resume and error retry.

```typescript
function smartPoll<T>(
  request: () => Observable<T>,
  intervalMs: number,
  options?: { retryCount?: number; pauseWhen$?: Observable<boolean> }
) {
  let poll$ = timer(0, intervalMs).pipe(
    switchMap(() => request().pipe(
      retry(options?.retryCount ?? 2),
      catchError(() => EMPTY)
    ))
  );

  // Pause when tab is hidden or custom condition
  if (options?.pauseWhen$) {
    poll$ = options.pauseWhen$.pipe(
      switchMap(paused => paused ? EMPTY : poll$)
    );
  }

  return poll$;
}

// Usage
const tabHidden$ = fromEvent(document, 'visibilitychange').pipe(
  map(() => document.hidden),
  startWith(false)
);

const status$ = smartPoll(() => api.getStatus(), 5000, {
  retryCount: 2,
  pauseWhen$: tabHidden$
});
```

---

## 12. Batch Processor

Accumulate items and process in batches.

```typescript
function createBatchProcessor<T, R>(
  processBatch: (items: T[]) => Observable<R>,
  options: { maxSize?: number; maxWaitMs?: number } = {}
) {
  const { maxSize = 10, maxWaitMs = 500 } = options;
  const queue$ = new Subject<T>();

  const results$ = queue$.pipe(
    bufferTime(maxWaitMs, null, maxSize),
    filter(batch => batch.length > 0),
    concatMap(batch => processBatch(batch).pipe(
      catchError(err => { console.error('Batch failed:', err); return EMPTY; })
    ))
  );

  return {
    add: (item: T) => queue$.next(item),
    results$,
    complete: () => queue$.complete()
  };
}

// Usage
const batcher = createBatchProcessor(
  (items: LogEntry[]) => api.sendLogs(items),
  { maxSize: 50, maxWaitMs: 1000 }
);

batcher.results$.subscribe();
events.forEach(e => batcher.add(e));
```

---

## Debug Utility

Reusable debug operator for development. Tracks subscriptions and helps identify leaks.

```typescript
import { Observable, MonoTypeOperatorFunction } from 'rxjs';
import { tap, finalize } from 'rxjs/operators';

// Basic debug: log next/error/complete
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

// Leak detector: track active subscription count per label
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

// Usage:
// source$.pipe(debug('my-stream'))
// source$.pipe(leakDetect('user-search'))
```

Remove all `debug()` / `leakDetect()` calls before production. Use proper logging library instead.
