#Requires AutoHotkey v2.1-alpha.16

;@region Observable
/**
 * AquaHotkey - Observable.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Observable.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Reactive streams (Observables) provide push-based, composable event handling.
 * Unlike pull-based iterators, Observables push values to subscribers as they
 * become available, making them ideal for async events, timers, and UI.
 *
 * This implementation follows the ReactiveX pattern with operators for
 * transformation, filtering, combination, and error handling.
 *
 * @example
 * ; Create an observable from interval timer
 * ticks := Observable.Interval(1000)
 *     .Map((n) => "Tick " . n)
 *     .Take(5)
 *     .Subscribe({
 *         Next: (v) => ToolTip(v),
 *         Complete: () => ToolTip("Done!")
 *     })
 *
 * ; Later: ticks() to unsubscribe
 */
class Observable {
    /**
     * Constructs an Observable from a subscribe function.
     *
     * The subscribe function receives an Observer and returns an unsubscribe
     * function. The Observer has Next, Error, and Complete methods.
     *
     * ```ahk
     * Subscribe(Observer) => UnsubscribeFn
     * ```
     *
     * @param   {Func}  Subscribe  subscription handler
     */
    __New(Subscribe) {
        this._subscribe := Subscribe
    }

    /**
     * Subscribe to the observable.
     *
     * @param   {Object}  Observer  {Next, Error?, Complete?}
     * @returns {Func}    unsubscribe function
     */
    Subscribe(Observer) {
        ; Normalize observer
        Obs := Observable._NormalizeObserver(Observer)
        return this._subscribe(Obs)
    }

    ;---------------------------------------------------------------------------
    ; Creation Operators
    ;---------------------------------------------------------------------------

    /**
     * Create an observable from individual values.
     *
     * @example
     * Observable.Of(1, 2, 3).Subscribe({Next: MsgBox})
     *
     * @param   {Any*}  Items  values to emit
     * @returns {Observable}
     */
    static Of(Items*) {
        return Observable((Obs) {
            for Item in Items {
                if (Obs._done)
                    break
                Obs.Next(Item)
            }
            Obs.Complete()
            return () => ""
        })
    }

    /**
     * Create an observable from an array.
     *
     * @param   {Array}  Arr
     * @returns {Observable}
     */
    static FromArray(Arr) => Observable.Of(Arr*)

    /**
     * Create an observable from a promise-like object.
     *
     * @param   {Object}  Promise  object with Then/Catch methods
     * @returns {Observable}
     */
    static FromPromise(Promise) {
        return Observable((Obs) {
            Promise.Then((V) {
                Obs.Next(V)
                Obs.Complete()
            }).Catch((E) => Obs.Error(E))
            return () => ""
        })
    }

    /**
     * Create an observable that emits values at intervals.
     *
     * @example
     * Observable.Interval(1000).Take(5).Subscribe({Next: MsgBox})
     *
     * @param   {Integer}  Ms  interval in milliseconds
     * @returns {Observable}
     */
    static Interval(Ms) {
        return Observable((Obs) {
            Count := 0
            Callback := () {
                if (!Obs._done)
                    Obs.Next(++Count)
            }
            SetTimer(Callback, Ms)
            return () => SetTimer(Callback, 0)
        })
    }

    /**
     * Create an observable that emits after a delay.
     *
     * @param   {Integer}  Ms     delay in milliseconds
     * @param   {Any}      Value  value to emit (default: 0)
     * @returns {Observable}
     */
    static Timer(Ms, Value := 0) {
        return Observable((Obs) {
            Callback := () {
                if (!Obs._done) {
                    Obs.Next(Value)
                    Obs.Complete()
                }
            }
            SetTimer(Callback, -Ms)
            return () => SetTimer(Callback, 0)
        })
    }

    /**
     * Create an observable from a GUI event.
     *
     * @example
     * clicks := Observable.FromEvent(myButton, "Click")
     *
     * @param   {Object}  Target  GUI control or other event source
     * @param   {String}  Event   event name
     * @returns {Observable}
     */
    static FromEvent(Target, Event) {
        return Observable((Obs) {
            Handler := (Args*) => Obs.Next(Args)
            Target.OnEvent(Event, Handler)
            return () => Target.OnEvent(Event, Handler, 0)
        })
    }

    /**
     * Create an observable from a hotkey.
     *
     * @param   {String}  HotkeyStr  hotkey string
     * @returns {Observable}
     */
    static FromHotkey(HotkeyStr) {
        return Observable((Obs) {
            Handler := (*) => Obs.Next(A_ThisHotkey)
            Hotkey(HotkeyStr, Handler, "On")
            return () => Hotkey(HotkeyStr, "Off")
        })
    }

    /**
     * Create an empty observable that completes immediately.
     *
     * @returns {Observable}
     */
    static Empty() {
        return Observable((Obs) {
            Obs.Complete()
            return () => ""
        })
    }

    /**
     * Create an observable that never emits or completes.
     *
     * @returns {Observable}
     */
    static Never() {
        return Observable((*) => () => "")
    }

    /**
     * Create an observable that immediately errors.
     *
     * @param   {Error}  Err
     * @returns {Observable}
     */
    static Throw(Err) {
        return Observable((Obs) {
            Obs.Error(Err)
            return () => ""
        })
    }

    /**
     * Create an observable from a generator function.
     *
     * @param   {Func}  GenFn  function that yields values via callback
     * @returns {Observable}
     */
    static Generate(GenFn) {
        return Observable((Obs) {
            try {
                GenFn((V) => !Obs._done ? Obs.Next(V) : false)
                Obs.Complete()
            } catch as E {
                Obs.Error(E)
            }
            return () => ""
        })
    }

    /**
     * Create a range observable.
     *
     * @param   {Integer}  Start  starting value
     * @param   {Integer}  Count  number of values
     * @returns {Observable}
     */
    static Range(Start, Count) {
        return Observable((Obs) {
            Loop Count {
                if (Obs._done)
                    break
                Obs.Next(Start + A_Index - 1)
            }
            Obs.Complete()
            return () => ""
        })
    }

    /**
     * Create an observable that repeats a value.
     *
     * @param   {Any}      Value  value to repeat
     * @param   {Integer}  Count  number of times (0 = infinite)
     * @returns {Observable}
     */
    static Repeat(Value, Count := 0) {
        return Observable((Obs) {
            if (Count = 0) {
                while (!Obs._done)
                    Obs.Next(Value)
            } else {
                Loop Count {
                    if (Obs._done)
                        break
                    Obs.Next(Value)
                }
            }
            Obs.Complete()
            return () => ""
        })
    }

    ;---------------------------------------------------------------------------
    ; Transformation Operators
    ;---------------------------------------------------------------------------

    /**
     * Transform each emitted value.
     *
     * @param   {Func}  Fn  transformation function
     * @returns {Observable}
     */
    Map(Fn) {
        return Observable((Obs) => this.Subscribe({
            Next: (X) => Obs.Next(Fn(X)),
            Error: (E) => Obs.Error(E),
            Complete: () => Obs.Complete()
        }))
    }

    /**
     * Transform and flatten nested observables.
     *
     * @param   {Func}  Fn  function returning Observable
     * @returns {Observable}
     */
    FlatMap(Fn) {
        return Observable((Obs) {
            Active := 1  ; Track active subscriptions
            OuterComplete := false
            Unsubs := []

            CheckComplete := () {
                if (OuterComplete && Active = 0)
                    Obs.Complete()
            }

            Unsub := this.Subscribe({
                Next: (X) {
                    Active++
                    Inner := Fn(X)
                    Unsubs.Push(Inner.Subscribe({
                        Next: (Y) => Obs.Next(Y),
                        Error: (E) => Obs.Error(E),
                        Complete: () {
                            Active--
                            CheckComplete()
                        }
                    }))
                },
                Error: (E) => Obs.Error(E),
                Complete: () {
                    Active--
                    OuterComplete := true
                    CheckComplete()
                }
            })

            return () {
                Unsub()
                for U in Unsubs
                    U()
            }
        })
    }

    /**
     * Flatten nested observables (alias for FlatMap with identity).
     *
     * @returns {Observable}
     */
    Flatten() => this.FlatMap((x) => x)

    /**
     * Switch to new observable, cancelling previous.
     *
     * @param   {Func}  Fn  function returning Observable
     * @returns {Observable}
     */
    SwitchMap(Fn) {
        return Observable((Obs) {
            InnerUnsub := ""
            OuterComplete := false

            Unsub := this.Subscribe({
                Next: (X) {
                    if (InnerUnsub)
                        InnerUnsub()
                    InnerUnsub := Fn(X).Subscribe({
                        Next: (Y) => Obs.Next(Y),
                        Error: (E) => Obs.Error(E),
                        Complete: () {
                            if (OuterComplete)
                                Obs.Complete()
                        }
                    })
                },
                Error: (E) => Obs.Error(E),
                Complete: () {
                    OuterComplete := true
                    if (!InnerUnsub)
                        Obs.Complete()
                }
            })

            return () {
                Unsub()
                if (InnerUnsub)
                    InnerUnsub()
            }
        })
    }

    /**
     * Accumulate values with a reducer.
     *
     * @param   {Func}  Fn    reducer function
     * @param   {Any}   Seed  initial value
     * @returns {Observable}
     */
    Scan(Fn, Seed) {
        return Observable((Obs) {
            Acc := Seed
            return this.Subscribe({
                Next: (X) => Obs.Next(Acc := Fn(Acc, X)),
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Reduce to final value (emits only on complete).
     *
     * @param   {Func}  Fn    reducer function
     * @param   {Any}   Seed  initial value
     * @returns {Observable}
     */
    Reduce(Fn, Seed) {
        return Observable((Obs) {
            Acc := Seed
            return this.Subscribe({
                Next: (X) => Acc := Fn(Acc, X),
                Error: (E) => Obs.Error(E),
                Complete: () {
                    Obs.Next(Acc)
                    Obs.Complete()
                }
            })
        })
    }

    /**
     * Buffer values into arrays.
     *
     * @param   {Integer}  Count  buffer size
     * @returns {Observable}
     */
    Buffer(Count) {
        return Observable((Obs) {
            Buf := []
            return this.Subscribe({
                Next: (X) {
                    Buf.Push(X)
                    if (Buf.Length = Count) {
                        Obs.Next(Buf)
                        Buf := []
                    }
                },
                Error: (E) => Obs.Error(E),
                Complete: () {
                    if (Buf.Length > 0)
                        Obs.Next(Buf)
                    Obs.Complete()
                }
            })
        })
    }

    /**
     * Map with index.
     *
     * @param   {Func}  Fn  (value, index) => result
     * @returns {Observable}
     */
    MapIndexed(Fn) {
        return Observable((Obs) {
            Idx := 0
            return this.Subscribe({
                Next: (X) => Obs.Next(Fn(X, ++Idx)),
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Pluck a property from emitted objects.
     *
     * @param   {String}  PropName
     * @returns {Observable}
     */
    Pluck(PropName) => this.Map((X) => X.%PropName%)

    ;---------------------------------------------------------------------------
    ; Filtering Operators
    ;---------------------------------------------------------------------------

    /**
     * Filter values by predicate.
     *
     * @param   {Func}  Pred
     * @returns {Observable}
     */
    Filter(Pred) {
        return Observable((Obs) => this.Subscribe({
            Next: (X) => Pred(X) ? Obs.Next(X) : "",
            Error: (E) => Obs.Error(E),
            Complete: () => Obs.Complete()
        }))
    }

    /**
     * Take first N values.
     *
     * @param   {Integer}  N
     * @returns {Observable}
     */
    Take(N) {
        return Observable((Obs) {
            Count := 0
            Unsub := ""
            Unsub := this.Subscribe({
                Next: (X) {
                    if (++Count <= N) {
                        Obs.Next(X)
                        if (Count = N) {
                            Obs.Complete()
                            if (Unsub)
                                Unsub()
                        }
                    }
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
            return Unsub
        })
    }

    /**
     * Take values while predicate is true.
     *
     * @param   {Func}  Pred
     * @returns {Observable}
     */
    TakeWhile(Pred) {
        return Observable((Obs) {
            Unsub := ""
            Unsub := this.Subscribe({
                Next: (X) {
                    if (Pred(X)) {
                        Obs.Next(X)
                    } else {
                        Obs.Complete()
                        if (Unsub)
                            Unsub()
                    }
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
            return Unsub
        })
    }

    /**
     * Skip first N values.
     *
     * @param   {Integer}  N
     * @returns {Observable}
     */
    Skip(N) {
        return Observable((Obs) {
            Count := 0
            return this.Subscribe({
                Next: (X) => ++Count > N ? Obs.Next(X) : "",
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Skip while predicate is true.
     *
     * @param   {Func}  Pred
     * @returns {Observable}
     */
    SkipWhile(Pred) {
        return Observable((Obs) {
            Skipping := true
            return this.Subscribe({
                Next: (X) {
                    if (Skipping && Pred(X))
                        return
                    Skipping := false
                    Obs.Next(X)
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Emit distinct consecutive values.
     *
     * @returns {Observable}
     */
    DistinctUntilChanged() {
        return Observable((Obs) {
            Prev := {}  ; Sentinel
            return this.Subscribe({
                Next: (X) {
                    if (Prev = {} || Prev != X) {
                        Prev := X
                        Obs.Next(X)
                    }
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Emit only first value.
     *
     * @returns {Observable}
     */
    First() => this.Take(1)

    /**
     * Emit only last value.
     *
     * @returns {Observable}
     */
    Last() {
        return Observable((Obs) {
            Last := {}
            return this.Subscribe({
                Next: (X) => Last := X,
                Error: (E) => Obs.Error(E),
                Complete: () {
                    if (Last != {})
                        Obs.Next(Last)
                    Obs.Complete()
                }
            })
        })
    }

    ;---------------------------------------------------------------------------
    ; Timing Operators
    ;---------------------------------------------------------------------------

    /**
     * Debounce emissions by time.
     *
     * @param   {Integer}  Ms
     * @returns {Observable}
     */
    Debounce(Ms) {
        return Observable((Obs) {
            Timer := ""
            return this.Subscribe({
                Next: (X) {
                    if (Timer)
                        SetTimer(Timer, 0)
                    Timer := () {
                        Obs.Next(X)
                        Timer := ""
                    }
                    SetTimer(Timer, -Ms)
                },
                Error: (E) => Obs.Error(E),
                Complete: () {
                    if (Timer)
                        SetTimer(Timer, 0)
                    Obs.Complete()
                }
            })
        })
    }

    /**
     * Throttle emissions to once per time period.
     *
     * @param   {Integer}  Ms
     * @returns {Observable}
     */
    Throttle(Ms) {
        return Observable((Obs) {
            LastEmit := 0
            return this.Subscribe({
                Next: (X) {
                    Now := A_TickCount
                    if (Now - LastEmit >= Ms) {
                        LastEmit := Now
                        Obs.Next(X)
                    }
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Delay each emission.
     *
     * @param   {Integer}  Ms
     * @returns {Observable}
     */
    Delay(Ms) {
        return Observable((Obs) {
            Timers := []
            return this.Subscribe({
                Next: (X) {
                    Timer := () => Obs.Next(X)
                    Timers.Push(Timer)
                    SetTimer(Timer, -Ms)
                },
                Error: (E) => Obs.Error(E),
                Complete: () {
                    Timer := () => Obs.Complete()
                    SetTimer(Timer, -Ms)
                }
            })
        })
    }

    /**
     * Add timestamp to each emission.
     *
     * @returns {Observable}
     */
    Timestamp() {
        return this.Map((X) => {value: X, timestamp: A_TickCount})
    }

    /**
     * Time interval between emissions.
     *
     * @returns {Observable}
     */
    TimeInterval() {
        return Observable((Obs) {
            Last := A_TickCount
            return this.Subscribe({
                Next: (X) {
                    Now := A_TickCount
                    Obs.Next({value: X, interval: Now - Last})
                    Last := Now
                },
                Error: (E) => Obs.Error(E),
                Complete: () => Obs.Complete()
            })
        })
    }

    /**
     * Timeout if no emission within duration.
     *
     * @param   {Integer}  Ms
     * @returns {Observable}
     */
    Timeout(Ms) {
        return Observable((Obs) {
            Timer := ""
            ResetTimer := () {
                if (Timer)
                    SetTimer(Timer, 0)
                Timer := () => Obs.Error(TimeoutError("Observable timeout"))
                SetTimer(Timer, -Ms)
            }
            ResetTimer()
            return this.Subscribe({
                Next: (X) {
                    ResetTimer()
                    Obs.Next(X)
                },
                Error: (E) {
                    if (Timer)
                        SetTimer(Timer, 0)
                    Obs.Error(E)
                },
                Complete: () {
                    if (Timer)
                        SetTimer(Timer, 0)
                    Obs.Complete()
                }
            })
        })
    }

    ;---------------------------------------------------------------------------
    ; Combination Operators
    ;---------------------------------------------------------------------------

    /**
     * Merge multiple observables.
     *
     * @param   {Observable*}  Observables
     * @returns {Observable}
     */
    static Merge(Observables*) {
        return Observable((Obs) {
            Completed := 0
            Unsubs := []
            for Source in Observables {
                Unsubs.Push(Source.Subscribe({
                    Next: (X) => Obs.Next(X),
                    Error: (E) => Obs.Error(E),
                    Complete: () {
                        if (++Completed = Observables.Length)
                            Obs.Complete()
                    }
                }))
            }
            return () {
                for U in Unsubs
                    U()
            }
        })
    }

    /**
     * Combine latest values from multiple observables.
     *
     * @param   {Observable*}  Observables
     * @returns {Observable}
     */
    static CombineLatest(Observables*) {
        return Observable((Obs) {
            Values := []
            HasValue := []
            Completed := 0
            Unsubs := []

            Loop Observables.Length {
                Values.Push("")
                HasValue.Push(false)
            }

            for I, Source in Observables {
                Idx := I
                Unsubs.Push(Source.Subscribe({
                    Next: (X) {
                        Values[Idx] := X
                        HasValue[Idx] := true
                        AllHave := true
                        for H in HasValue {
                            if (!H) {
                                AllHave := false
                                break
                            }
                        }
                        if (AllHave)
                            Obs.Next(Values.Clone())
                    },
                    Error: (E) => Obs.Error(E),
                    Complete: () {
                        if (++Completed = Observables.Length)
                            Obs.Complete()
                    }
                }))
            }

            return () {
                for U in Unsubs
                    U()
            }
        })
    }

    /**
     * Zip observables together.
     *
     * @param   {Observable*}  Observables
     * @returns {Observable}
     */
    static Zip(Observables*) {
        return Observable((Obs) {
            Queues := []
            Completed := []
            Unsubs := []

            Loop Observables.Length {
                Queues.Push([])
                Completed.Push(false)
            }

            TryEmit := () {
                AllHave := true
                for Q in Queues {
                    if (Q.Length = 0) {
                        AllHave := false
                        break
                    }
                }
                if (AllHave) {
                    Result := []
                    for Q in Queues
                        Result.Push(Q.RemoveAt(1))
                    Obs.Next(Result)
                }
            }

            CheckComplete := () {
                for I, C in Completed {
                    if (C && Queues[I].Length = 0) {
                        Obs.Complete()
                        return
                    }
                }
            }

            for I, Source in Observables {
                Idx := I
                Unsubs.Push(Source.Subscribe({
                    Next: (X) {
                        Queues[Idx].Push(X)
                        TryEmit()
                    },
                    Error: (E) => Obs.Error(E),
                    Complete: () {
                        Completed[Idx] := true
                        CheckComplete()
                    }
                }))
            }

            return () {
                for U in Unsubs
                    U()
            }
        })
    }

    /**
     * Concatenate observables sequentially.
     *
     * @param   {Observable*}  Observables
     * @returns {Observable}
     */
    static Concat(Observables*) {
        return Observable((Obs) {
            Idx := 1
            CurrentUnsub := ""

            SubscribeNext() {
                if (Idx > Observables.Length) {
                    Obs.Complete()
                    return
                }
                CurrentUnsub := Observables[Idx].Subscribe({
                    Next: (X) => Obs.Next(X),
                    Error: (E) => Obs.Error(E),
                    Complete: () {
                        Idx++
                        SubscribeNext()
                    }
                })
            }

            SubscribeNext()
            return () {
                if (CurrentUnsub)
                    CurrentUnsub()
            }
        })
    }

    /**
     * Start with specified values.
     *
     * @param   {Any*}  Values
     * @returns {Observable}
     */
    StartWith(Values*) {
        return Observable.Concat(Observable.Of(Values*), this)
    }

    /**
     * Combine with another observable using combiner function.
     *
     * @param   {Observable}  Other
     * @param   {Func}        Fn
     * @returns {Observable}
     */
    CombineWith(Other, Fn) {
        return Observable.CombineLatest(this, Other)
            .Map((Arr) => Fn(Arr[1], Arr[2]))
    }

    /**
     * Race: emit from whichever observable emits first.
     *
     * @param   {Observable*}  Observables
     * @returns {Observable}
     */
    static Race(Observables*) {
        return Observable((Obs) {
            Winner := ""
            Unsubs := []

            for I, Source in Observables {
                Idx := I
                Unsubs.Push(Source.Subscribe({
                    Next: (X) {
                        if (Winner = "") {
                            Winner := Idx
                            ; Unsubscribe from losers
                            for J, U in Unsubs {
                                if (J != Winner)
                                    U()
                            }
                        }
                        if (Winner = Idx)
                            Obs.Next(X)
                    },
                    Error: (E) {
                        if (Winner = "" || Winner = Idx)
                            Obs.Error(E)
                    },
                    Complete: () {
                        if (Winner = Idx)
                            Obs.Complete()
                    }
                }))
            }

            return () {
                for U in Unsubs
                    U()
            }
        })
    }

    ;---------------------------------------------------------------------------
    ; Error Handling
    ;---------------------------------------------------------------------------

    /**
     * Catch errors and switch to fallback.
     *
     * @param   {Func}  Handler  (Error) => Observable
     * @returns {Observable}
     */
    CatchError(Handler) {
        return Observable((Obs) {
            Unsub := this.Subscribe({
                Next: (X) => Obs.Next(X),
                Error: (E) => Handler(E).Subscribe(Obs),
                Complete: () => Obs.Complete()
            })
            return Unsub
        })
    }

    /**
     * Retry on error.
     *
     * @param   {Integer}  Count  max retries
     * @returns {Observable}
     */
    Retry(Count) {
        return Observable((Obs) {
            Attempts := 0
            Unsub := ""

            Subscribe := () {
                Unsub := this.Subscribe({
                    Next: (X) => Obs.Next(X),
                    Error: (E) {
                        if (++Attempts <= Count)
                            Subscribe()
                        else
                            Obs.Error(E)
                    },
                    Complete: () => Obs.Complete()
                })
            }

            Subscribe()
            return () {
                if (Unsub)
                    Unsub()
            }
        })
    }

    /**
     * Perform side effect on each emission.
     *
     * @param   {Func}  Fn
     * @returns {Observable}
     */
    Tap(Fn) {
        return Observable((Obs) => this.Subscribe({
            Next: (X) {
                Fn(X)
                Obs.Next(X)
            },
            Error: (E) => Obs.Error(E),
            Complete: () => Obs.Complete()
        }))
    }

    /**
     * Finalize: run cleanup on complete or error.
     *
     * @param   {Func}  Fn
     * @returns {Observable}
     */
    Finalize(Fn) {
        return Observable((Obs) {
            return this.Subscribe({
                Next: (X) => Obs.Next(X),
                Error: (E) {
                    Fn()
                    Obs.Error(E)
                },
                Complete: () {
                    Fn()
                    Obs.Complete()
                }
            })
        })
    }

    ;---------------------------------------------------------------------------
    ; Utility
    ;---------------------------------------------------------------------------

    /**
     * Share subscription among multiple subscribers.
     *
     * @returns {Observable}
     */
    Share() {
        Subscribers := []
        SourceUnsub := ""
        Source := this

        return Observable((Obs) {
            Subscribers.Push(Obs)

            if (Subscribers.Length = 1) {
                SourceUnsub := Source.Subscribe({
                    Next: (X) {
                        for S in Subscribers
                            S.Next(X)
                    },
                    Error: (E) {
                        for S in Subscribers
                            S.Error(E)
                    },
                    Complete: () {
                        for S in Subscribers
                            S.Complete()
                    }
                })
            }

            return () {
                for I, S in Subscribers {
                    if (S = Obs) {
                        Subscribers.RemoveAt(I)
                        break
                    }
                }
                if (Subscribers.Length = 0 && SourceUnsub) {
                    SourceUnsub()
                    SourceUnsub := ""
                }
            }
        })
    }

    /**
     * Convert to array (collects all values).
     *
     * @returns {Observable}
     */
    ToArray() => this.Reduce((Acc, X) => (Acc.Push(X), Acc), [])

    /**
     * Normalize observer object.
     */
    static _NormalizeObserver(Obs) {
        return {
            _done: false,
            Next: (X) {
                if (!this._done && Obs.HasProp("Next"))
                    Obs.Next(X)
            },
            Error: (E) {
                if (!this._done) {
                    this._done := true
                    if (Obs.HasProp("Error"))
                        Obs.Error(E)
                    else
                        throw E
                }
            },
            Complete: () {
                if (!this._done) {
                    this._done := true
                    if (Obs.HasProp("Complete"))
                        Obs.Complete()
                }
            }
        }
    }
}
;@endregion

;@region Subject
/**
 * Subject - Both an Observable and an Observer.
 *
 * A Subject can multicast to multiple observers and can be manually
 * pushed values from outside.
 *
 * @example
 * subj := Subject()
 * subj.Subscribe({Next: (x) => MsgBox(x)})
 * subj.Next("Hello!")  ; Triggers subscriber
 */
class Subject extends Observable {
    __New() {
        this._subscribers := []
        this._done := false
        super.__New((Obs) {
            this._subscribers.Push(Obs)
            return () {
                for I, S in this._subscribers {
                    if (S = Obs) {
                        this._subscribers.RemoveAt(I)
                        break
                    }
                }
            }
        })
    }

    /**
     * Emit a value to all subscribers.
     */
    Next(Value) {
        if (!this._done)
            for S in this._subscribers
                S.Next(Value)
    }

    /**
     * Emit an error to all subscribers.
     */
    Error(Err) {
        if (!this._done) {
            this._done := true
            for S in this._subscribers
                S.Error(Err)
        }
    }

    /**
     * Complete all subscribers.
     */
    Complete() {
        if (!this._done) {
            this._done := true
            for S in this._subscribers
                S.Complete()
        }
    }

    /**
     * Get as Observable (hides Subject methods).
     */
    AsObservable() => Observable((Obs) => this.Subscribe(Obs))
}

/**
 * BehaviorSubject - Subject with current value.
 */
class BehaviorSubject extends Subject {
    __New(InitialValue) {
        this._value := InitialValue
        super.__New()
    }

    Value => this._value

    Next(Value) {
        this._value := Value
        super.Next(Value)
    }

    Subscribe(Observer) {
        Obs := Observable._NormalizeObserver(Observer)
        Obs.Next(this._value)
        return super.Subscribe(Obs)
    }
}

/**
 * ReplaySubject - Subject that replays past values to new subscribers.
 */
class ReplaySubject extends Subject {
    __New(BufferSize := 0) {
        this._buffer := []
        this._bufferSize := BufferSize
        super.__New()
    }

    Next(Value) {
        this._buffer.Push(Value)
        if (this._bufferSize > 0 && this._buffer.Length > this._bufferSize)
            this._buffer.RemoveAt(1)
        super.Next(Value)
    }

    Subscribe(Observer) {
        Obs := Observable._NormalizeObserver(Observer)
        for V in this._buffer
            Obs.Next(V)
        return super.Subscribe(Obs)
    }
}
;@endregion

;@region TimeoutError
class TimeoutError extends Error {
}
;@endregion

;@region Extensions
class AquaHotkey_Observable extends AquaHotkey {
    class Array {
        /**
         * Convert array to Observable.
         *
         * @returns {Observable}
         */
        ToObservable() => Observable.FromArray(this)
    }
}
;@endregion
