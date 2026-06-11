# Framework Interop

How to bridge RxJS with Angular Signals and React hooks without leaking subscriptions.

## Angular Signals Interop (16+)

Angular's `@angular/core/rxjs-interop` bridges Signals and Observables. Gradually adopt Signals without rewriting existing Observable code.

### Bridging API

```typescript
import { toSignal, toObservable, takeUntilDestroyed } from '@angular/core/rxjs-interop';

@Component({ /* ... */ })
export class SearchComponent {
  private searchService = inject(SearchService);
  private destroyRef = inject(DestroyRef);

  // Signal -> Observable -> Signal pipeline (auto-unsubscribes on destroy)
  query = signal('');
  results = toSignal(
    toObservable(this.query).pipe(
      debounceTime(300),
      switchMap(q => this.searchService.search(q))
    ),
    { initialValue: [] }
  );

  // takeUntilDestroyed replaces manual destroy$ + takeUntil boilerplate
  ngOnInit() {
    someStream$.pipe(
      takeUntilDestroyed(this.destroyRef)
    ).subscribe(val => this.handleValue(val));
  }
}
```

### Choosing Signal vs Observable

- **Use `toSignal()`** when the template consumes the value (replaces `async` pipe). Signals are synchronous in the template and play well with fine-grained change detection.
- **Keep as Observable** when you need operators like `switchMap`, `debounceTime`, `combineLatest` for complex stream logic. `toObservable()` / `toSignal()` cross the boundary at the edges only.
- **Don't bounce repeatedly** between signal and observable in the same pipeline — each conversion adds overhead and can hide subscription bugs.

### `takeUntilDestroyed` Notes

- Inside an injection context (constructor, field initializer), no argument needed: `takeUntilDestroyed()`.
- Outside injection context (inside `ngOnInit`, methods), pass `DestroyRef` explicitly: `takeUntilDestroyed(this.destroyRef)`.

## React Hooks with RxJS

### Generic `useObservable` hook

```typescript
import { useEffect, useState, useRef } from 'react';
import { Observable, Subject, Subscription } from 'rxjs';

function useObservable<T>(observable$: Observable<T>, initialValue: T): T {
  const [value, setValue] = useState<T>(initialValue);
  useEffect(() => {
    const sub = observable$.subscribe(setValue);
    return () => sub.unsubscribe();
  }, [observable$]);
  return value;
}
```

### `useEventObservable` — bridge React events to a stream

```typescript
function useEventObservable<T>(): [Subject<T>, Observable<T>] {
  const subject = useRef(new Subject<T>());
  useEffect(() => () => subject.current.complete(), []);
  return [subject.current, subject.current.asObservable()];
}
```

### Full Example

```typescript
function SearchBox() {
  const [input$, inputEvents$] = useEventObservable<string>();

  const results = useObservable(
    inputEvents$.pipe(
      debounceTime(300),
      distinctUntilChanged(),
      switchMap(q => fetchResults(q)),
      catchError(() => of([]))
    ),
    []
  );

  return <input onChange={e => input$.next(e.target.value)} />;
}
```

### Gotchas

- **Observable identity in deps**: If you recreate the Observable every render (e.g., inline `.pipe()` in component body), `useEffect` re-subscribes every render. Memoize with `useMemo` or lift the pipeline outside the component.
- **Subject complete on unmount**: The cleanup `subject.current.complete()` is necessary — otherwise downstream consumers never get a completion signal.
- **Don't use Observables for pure React state** — plain `useState` is simpler. Reach for RxJS when you need debounce / cancellation / stream combination.
