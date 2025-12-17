#Requires AutoHotkey v2.1-alpha.16

;@region Cont
/**
 * AquaHotkey - Cont.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Cont.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * The Continuation Monad captures "the rest of the computation" as a first-class
 * value, enabling powerful control flow abstractions like early return, coroutines,
 * backtracking, and delimited continuations.
 *
 * A continuation represents "what happens next" in a computation. By reifying
 * this concept, we gain unprecedented control over program flow.
 *
 * @example
 * ; Early return using call/cc
 * FindFirst(Arr, Pred) {
 *     return Cont.CallCC((return_) {
 *         for Item in Arr {
 *             if Pred(Item)
 *                 return return_(Optional(Item))
 *         }
 *         return Cont.Of(Optional())
 *     }).RunCont((x) => x)
 * }
 *
 * @example
 * ; Computation that can be suspended and resumed
 * computation := Cont.Of(5)
 *     .Map((x) => x * 2)
 *     .FlatMap((x) => Cont.Of(x + 1))
 *
 * result := computation.RunCont((x) => "Result: " . x) ; "Result: 11"
 */
class Cont {
    /**
     * Constructs a new Continuation from a runner function.
     *
     * The runner takes a continuation (callback) and produces a result
     * by eventually calling that continuation with a value.
     *
     * ```ahk
     * Run(K: Func) => Any  ; K is the continuation
     * ```
     *
     * @param   {Func}  Run  the continuation runner
     */
    __New(Run) {
        this._run := Run
    }

    /**
     * Run the continuation with a final handler.
     * The handler processes the final value of the computation.
     *
     * @example
     * Cont.Of(42).RunCont((x) => x * 2) ; 84
     *
     * @param   {Func}  K  the final continuation
     * @returns {Any}
     */
    RunCont(K) => this._run(K)

    /**
     * Run the continuation with identity, extracting the value.
     *
     * @returns {Any}
     */
    Run() => this._run((x) => x)

    /**
     * Functor map: transform the eventual value.
     *
     * @example
     * Cont.Of(5).Map((x) => x * 2).Run() ; 10
     *
     * @param   {Func}  Fn  transformation function
     * @returns {Cont}
     */
    Map(Fn) => Cont((K) => this._run((A) => K(Fn(A))))

    /**
     * Monadic bind: chain computations.
     *
     * @example
     * Cont.Of(5).FlatMap((x) => Cont.Of(x * 2)).Run() ; 10
     *
     * @param   {Func}  Fn  function returning a Cont
     * @returns {Cont}
     */
    FlatMap(Fn) => Cont((K) => this._run((A) => Fn(A)._run(K)))

    /**
     * Applicative: apply a function wrapped in Cont to this value.
     *
     * @param   {Cont}  ContFn  continuation containing a function
     * @returns {Cont}
     */
    Ap(ContFn) => ContFn.FlatMap((Fn) => this.Map(Fn))

    /**
     * Lift a pure value into the Continuation monad.
     *
     * @example
     * Cont.Of(42).Run() ; 42
     *
     * @param   {Any}  Value  the value to lift
     * @returns {Cont}
     */
    static Of(Value) => Cont((K) => K(Value))

    /**
     * Alias for `Of`.
     * @param   {Any}  Value
     * @returns {Cont}
     */
    static Pure(Value) => Cont.Of(Value)

    /**
     * Create a continuation from a callback-style function.
     *
     * @example
     * ; Convert callback-based API to continuation
     * readFile := Cont.FromCallback((cb) => FileReadAsync(path, cb))
     *
     * @param   {Func}  SetupFn  function that takes a callback
     * @returns {Cont}
     */
    static FromCallback(SetupFn) => Cont((K) => SetupFn(K))

    ;---------------------------------------------------------------------------
    ; Control Flow Operations
    ;---------------------------------------------------------------------------

    /**
     * Call with Current Continuation (call/cc).
     *
     * The most powerful control flow primitive. Captures the current
     * continuation and passes it to the provided function. The captured
     * continuation can be called to "jump back" to this point with a value.
     *
     * @example
     * ; Early return pattern
     * Cont.CallCC((exit) {
     *     ; ... some computation ...
     *     if (condition)
     *         return exit("early result")  ; Immediately returns "early result"
     *     ; ... more computation ...
     *     return Cont.Of("normal result")
     * })
     *
     * @param   {Func}  Fn  function receiving the current continuation
     * @returns {Cont}
     */
    static CallCC(Fn) {
        return Cont((K) {
            ; Create an "escape" continuation that, when called,
            ; immediately invokes K with the given value
            Escape := (A) => Cont((*) => K(A))
            return Fn(Escape)._run(K)
        })
    }

    /**
     * Reset: delimits the extent of a continuation.
     * Creates a "boundary" for shift operations.
     *
     * @example
     * ; Delimited continuation example
     * result := Cont.Reset(
     *     Cont.Of(1).FlatMap((x) =>
     *         Cont.Shift((k) => Cont.Of(k(k(x))))
     *     ).Map((x) => x + 1)
     * ).Run()  ; ((1 + 1) + 1) = 3
     *
     * @param   {Cont}  ContComp  computation to delimit
     * @returns {Cont}
     */
    static Reset(ContComp) => Cont((K) => K(ContComp._run((x) => x)))

    /**
     * Shift: captures the current delimited continuation up to Reset.
     *
     * @param   {Func}  Fn  function receiving the captured continuation
     * @returns {Cont}
     */
    static Shift(Fn) => Cont((K) => Fn((V) => Cont.Of(K(V)))._run((x) => x))

    /**
     * Sequence multiple continuations, returning the last result.
     *
     * @param   {Cont*}  Conts  continuations to sequence
     * @returns {Cont}
     */
    static Sequence(Conts*) {
        if (Conts.Length = 0)
            return Cont.Of("")
        Result := Conts[1]
        Loop Conts.Length - 1
            Result := Result.FlatMap((*) => Conts[A_Index + 1])
        return Result
    }

    /**
     * Traverse an array with a continuation-producing function.
     *
     * @param   {Array}  Arr  array to traverse
     * @param   {Func}   Fn   function returning Cont for each element
     * @returns {Cont}
     */
    static Traverse(Arr, Fn) {
        if (Arr.Length = 0)
            return Cont.Of([])

        return Fn(Arr[1]).FlatMap((First) {
            Rest := []
            Loop Arr.Length - 1
                Rest.Push(Arr[A_Index + 1])

            return Cont.Traverse(Rest, Fn).Map((Tail) {
                return [First, Tail*]
            })
        })
    }

    /**
     * Parallel applicative combining.
     *
     * @param   {Cont*}  Conts  continuations to combine
     * @returns {Cont}
     */
    static All(Conts*) {
        if (Conts.Length = 0)
            return Cont.Of([])

        return Conts[1].FlatMap((First) {
            Rest := []
            Loop Conts.Length - 1
                Rest.Push(Conts[A_Index + 1])

            return Cont.All(Rest*).Map((Tail) {
                return [First, Tail*]
            })
        })
    }

    /**
     * Guard: continues only if condition is true.
     * Used for filtering in continuation-based computations.
     *
     * @param   {Boolean}  Cond  condition to check
     * @returns {Cont}
     */
    static Guard(Cond) {
        return Cont.CallCC((exit) {
            if (!Cond)
                return exit([])  ; Empty result signals failure
            return Cont.Of(true)
        })
    }

    /**
     * Choice: non-deterministic choice between values.
     * Each value becomes a potential "path" in the computation.
     *
     * @param   {Array}  Choices  array of values to choose from
     * @returns {Cont}
     */
    static Choose(Choices) {
        return Cont((K) {
            Results := []
            for Choice in Choices
                Results.Push(K(Choice))
            return Results
        })
    }

    ;---------------------------------------------------------------------------
    ; Exception Handling via Continuations
    ;---------------------------------------------------------------------------

    /**
     * Wrap a computation with error handling.
     * Catches exceptions and handles them via continuation.
     *
     * @param   {Cont}  Computation  the computation to protect
     * @param   {Func}  Handler      error handler function
     * @returns {Cont}
     */
    static TryCatch(Computation, Handler) {
        return Cont((K) {
            try {
                return Computation._run(K)
            } catch as E {
                return Handler(E)._run(K)
            }
        })
    }

    /**
     * Throw an error in continuation style.
     *
     * @param   {Error}  Err  the error to throw
     * @returns {Cont}
     */
    static Throw(Err) => Cont((*) { throw Err })

    ;---------------------------------------------------------------------------
    ; Utility Methods
    ;---------------------------------------------------------------------------

    /**
     * Create a continuation that applies a function with an argument.
     *
     * @param   {Func}  Fn   the function to apply
     * @param   {Any}   Arg  the argument
     * @returns {Cont}
     */
    static Apply(Fn, Arg) => Cont.Of(Arg).Map(Fn)

    /**
     * Lift a binary function into continuations.
     *
     * @param   {Func}  Fn  binary function
     * @param   {Cont}  Ca  first continuation
     * @param   {Cont}  Cb  second continuation
     * @returns {Cont}
     */
    static LiftA2(Fn, Ca, Cb) {
        return Ca.FlatMap((A) => Cb.Map((B) => Fn(A, B)))
    }

    /**
     * Join: flatten nested continuations.
     *
     * @param   {Cont}  Nested  Cont containing a Cont
     * @returns {Cont}
     */
    static Join(Nested) => Nested.FlatMap((x) => x)

    /**
     * Forever: repeat a continuation indefinitely.
     * Useful for event loops and servers.
     *
     * @param   {Cont}  C  continuation to repeat
     * @returns {Cont}
     */
    static Forever(C) => C.FlatMap((*) => Cont.Forever(C))

    /**
     * Replicate: run a continuation N times, collecting results.
     *
     * @param   {Integer}  N  number of times
     * @param   {Cont}     C  continuation to replicate
     * @returns {Cont}
     */
    static Replicate(N, C) {
        if (N <= 0)
            return Cont.Of([])
        return C.FlatMap((X) {
            return Cont.Replicate(N - 1, C).Map((Rest) => [X, Rest*])
        })
    }

    /**
     * String representation.
     * @returns {String}
     */
    ToString() => "Cont(...)"
}
;@endregion

;@region ContT
/**
 * ContT - Continuation Monad Transformer.
 *
 * Allows stacking continuations on top of other monads,
 * enabling effects like early return within Option, Result, etc.
 *
 * @example
 * ; ContT over Optional
 * contOpt := ContT((k) => k(5).Map((x) => x * 2))
 */
class ContT {
    /**
     * Constructs a ContT from a runner function.
     *
     * ```ahk
     * Run(K: Func) => M<Any>  ; K returns a value in monad M
     * ```
     *
     * @param   {Func}  Run
     */
    __New(Run) {
        this._run := Run
    }

    /**
     * Run with a continuation that returns values in the inner monad.
     *
     * @param   {Func}  K  continuation returning inner monad
     * @returns {Any}
     */
    RunContT(K) => this._run(K)

    /**
     * Map over the final result.
     *
     * @param   {Func}  Fn
     * @returns {ContT}
     */
    Map(Fn) => ContT((K) => this._run((A) => K(Fn(A))))

    /**
     * Monadic bind.
     *
     * @param   {Func}  Fn
     * @returns {ContT}
     */
    FlatMap(Fn) => ContT((K) => this._run((A) => Fn(A)._run(K)))

    /**
     * Lift a value into ContT.
     *
     * @param   {Any}  Value
     * @returns {ContT}
     */
    static Of(Value) => ContT((K) => K(Value))

    /**
     * Lift an inner monad value into ContT.
     *
     * @param   {Any}  M  value in inner monad
     * @returns {ContT}
     */
    static Lift(M) => ContT((K) => M.FlatMap(K))

    /**
     * Call/cc for the transformer.
     *
     * @param   {Func}  Fn
     * @returns {ContT}
     */
    static CallCC(Fn) {
        return ContT((K) {
            Escape := (A) => ContT((*) => K(A))
            return Fn(Escape)._run(K)
        })
    }
}
;@endregion

;@region Reader
/**
 * Reader - Computation depending on an environment.
 *
 * The Reader monad represents computations that read from a shared environment.
 * Perfect for dependency injection and configuration.
 *
 * @example
 * ; Database connection as environment
 * getUser := Reader((env) => env.db.query("SELECT * FROM users"))
 * result := getUser.Run({db: myConnection})
 */
class Reader {
    /**
     * Constructs a Reader from a runner function.
     *
     * ```ahk
     * Run(Env) => Value
     * ```
     *
     * @param   {Func}  Run
     */
    __New(Run) {
        this._run := Run
    }

    /**
     * Run the reader with an environment.
     *
     * @param   {Any}  Env  the environment
     * @returns {Any}
     */
    Run(Env) => this._run(Env)

    /**
     * Map over the result.
     *
     * @param   {Func}  Fn
     * @returns {Reader}
     */
    Map(Fn) => Reader((Env) => Fn(this._run(Env)))

    /**
     * Monadic bind.
     *
     * @param   {Func}  Fn
     * @returns {Reader}
     */
    FlatMap(Fn) => Reader((Env) => Fn(this._run(Env))._run(Env))

    /**
     * Lift a value into Reader.
     *
     * @param   {Any}  Value
     * @returns {Reader}
     */
    static Of(Value) => Reader((*) => Value)

    /**
     * Get the environment.
     *
     * @returns {Reader}
     */
    static Ask() => Reader((Env) => Env)

    /**
     * Get part of the environment.
     *
     * @param   {Func}  Fn  selector function
     * @returns {Reader}
     */
    static Asks(Fn) => Reader((Env) => Fn(Env))

    /**
     * Run with a modified environment.
     *
     * @param   {Func}  Fn  environment modifier
     * @returns {Reader}
     */
    Local(Fn) => Reader((Env) => this._run(Fn(Env)))
}
;@endregion

;@region State
/**
 * State - Computation with mutable state.
 *
 * The State monad threads state through a computation,
 * enabling pure functional state handling.
 *
 * @example
 * counter := State.Get()
 *     .FlatMap((n) => State.Put(n + 1))
 *     .FlatMap((*) => State.Get())
 *
 * result := counter.Run(0) ; {value: 1, state: 1}
 */
class State {
    /**
     * Constructs a State from a runner function.
     *
     * ```ahk
     * Run(S) => {value, state}
     * ```
     *
     * @param   {Func}  Run
     */
    __New(Run) {
        this._run := Run
    }

    /**
     * Run the state computation with initial state.
     *
     * @param   {Any}  InitState  initial state
     * @returns {Object}  {value, state}
     */
    Run(InitState) => this._run(InitState)

    /**
     * Run and return only the value.
     *
     * @param   {Any}  InitState
     * @returns {Any}
     */
    Eval(InitState) => this._run(InitState).value

    /**
     * Run and return only the final state.
     *
     * @param   {Any}  InitState
     * @returns {Any}
     */
    Exec(InitState) => this._run(InitState).state

    /**
     * Map over the result value.
     *
     * @param   {Func}  Fn
     * @returns {State}
     */
    Map(Fn) {
        return State((S) {
            R := this._run(S)
            return {value: Fn(R.value), state: R.state}
        })
    }

    /**
     * Monadic bind.
     *
     * @param   {Func}  Fn
     * @returns {State}
     */
    FlatMap(Fn) {
        return State((S) {
            R := this._run(S)
            return Fn(R.value)._run(R.state)
        })
    }

    /**
     * Lift a value into State.
     *
     * @param   {Any}  Value
     * @returns {State}
     */
    static Of(Value) => State((S) => {value: Value, state: S})

    /**
     * Get the current state.
     *
     * @returns {State}
     */
    static Get() => State((S) => {value: S, state: S})

    /**
     * Set the state.
     *
     * @param   {Any}  NewState
     * @returns {State}
     */
    static Put(NewState) => State((*) => {value: "", state: NewState})

    /**
     * Modify the state with a function.
     *
     * @param   {Func}  Fn
     * @returns {State}
     */
    static Modify(Fn) => State((S) => {value: "", state: Fn(S)})

    /**
     * Get part of the state.
     *
     * @param   {Func}  Fn
     * @returns {State}
     */
    static Gets(Fn) => State((S) => {value: Fn(S), state: S})
}
;@endregion

;@region Extensions
class AquaHotkey_Cont extends AquaHotkey {
    class Func {
        /**
         * Lift this function into a continuation.
         *
         * @returns {Cont}
         */
        ToCont() {
            Fn := this
            return Cont((K) => K(Fn()))
        }

        /**
         * Create a reader that applies this function to the environment.
         *
         * @returns {Reader}
         */
        ToReader() => Reader(this)
    }

    class Array {
        /**
         * Traverse this array with a continuation-producing function.
         *
         * @param   {Func}  Fn
         * @returns {Cont}
         */
        TraverseCont(Fn) => Cont.Traverse(this, Fn)

        /**
         * Convert array elements to continuations and collect results.
         *
         * @returns {Cont}
         */
        SequenceCont() => Cont.All(this*)
    }
}
;@endregion
