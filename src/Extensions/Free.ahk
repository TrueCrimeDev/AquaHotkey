#Requires AutoHotkey v2.1-alpha.16

;@region Free
/**
 * AquaHotkey - Free.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Free.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * The Free Monad separates the description of effects from their interpretation.
 * This enables:
 * - Building DSLs (Domain Specific Languages)
 * - Testing effects with mock interpreters
 * - Composing different effect systems
 * - Separation of concerns between "what" and "how"
 *
 * The Free monad is built from any Functor F, giving you a monad for free.
 * Effects are described as an abstract syntax tree, then interpreted.
 *
 * @example
 * ; Define a Console DSL
 * print := (msg) => Free.LiftF({op: "Print", msg: msg, next: (x) => x})
 * read := () => Free.LiftF({op: "Read", next: (x) => x})
 *
 * ; Build a program (just a description, no side effects yet)
 * program := print("What's your name?")
 *     .FlatMap((*) => read())
 *     .FlatMap((name) => print("Hello, " . name . "!"))
 *
 * ; Interpret with real console
 * program.Interpret((effect) {
 *     switch effect.op {
 *         case "Print":
 *             MsgBox(effect.msg)
 *             return Free.Pure("")
 *         case "Read":
 *             return Free.Pure(InputBox("Input").Value)
 *     }
 * })
 */

;---------------------------------------------------------------------------
;@region Free Monad
/**
 * Free - The Free Monad.
 *
 * Either Pure(value) or Suspend(functor containing Free).
 */
class Free {
    /**
     * Lift a pure value into the Free monad.
     *
     * @param   {Any}  Value
     * @returns {FreePure}
     */
    static Pure(Value) => FreePure(Value)

    /**
     * Suspend an effect for later interpretation.
     *
     * @param   {Object}  Effect  functor containing Free continuation
     * @returns {FreeSuspend}
     */
    static Suspend(Effect) => FreeSuspend(Effect)

    /**
     * Lift an effect into Free.
     * The effect must have a 'next' property that's a function.
     *
     * @example
     * print := (msg) => Free.LiftF({op: "Print", msg: msg, next: (x) => x})
     *
     * @param   {Object}  Effect  effect with 'next' continuation
     * @returns {Free}
     */
    static LiftF(Effect) {
        ; Wrap the effect so its 'next' returns a FreePure
        Mapped := Effect.Clone()
        OrigNext := Effect.next
        Mapped.next := (X) => Free.Pure(OrigNext(X))
        return Free.Suspend(Mapped)
    }

    /**
     * Create a Free computation that fails with an error.
     *
     * @param   {Error}  Err
     * @returns {Free}
     */
    static Throw(Err) => Free.Suspend({op: "Throw", error: Err, next: (*) => ""})

    /**
     * Sequence multiple Free computations.
     *
     * @param   {Free*}  Frees
     * @returns {Free}
     */
    static Sequence(Frees*) {
        if (Frees.Length = 0)
            return Free.Pure([])

        return Frees[1].FlatMap((First) {
            Rest := []
            Loop Frees.Length - 1
                Rest.Push(Frees[A_Index + 1])
            return Free.Sequence(Rest*).Map((Tail) => [First, Tail*])
        })
    }

    /**
     * Traverse an array with a Free-returning function.
     *
     * @param   {Array}  Arr
     * @param   {Func}   Fn
     * @returns {Free}
     */
    static Traverse(Arr, Fn) {
        if (Arr.Length = 0)
            return Free.Pure([])

        return Fn(Arr[1]).FlatMap((First) {
            Rest := []
            Loop Arr.Length - 1
                Rest.Push(Arr[A_Index + 1])
            return Free.Traverse(Rest, Fn).Map((Tail) => [First, Tail*])
        })
    }

    /**
     * Replicate a Free computation N times.
     *
     * @param   {Integer}  N
     * @param   {Free}     F
     * @returns {Free}
     */
    static Replicate(N, F) {
        if (N <= 0)
            return Free.Pure([])
        return F.FlatMap((X) {
            return Free.Replicate(N - 1, F).Map((Rest) => [X, Rest*])
        })
    }

    /**
     * Create a Free that does nothing (returns unit).
     *
     * @returns {Free}
     */
    static Unit() => Free.Pure("")

    /**
     * Forever: repeat a Free computation indefinitely.
     * (Be careful - only use with effects that can terminate)
     *
     * @param   {Free}  F
     * @returns {Free}
     */
    static Forever(F) => F.FlatMap((*) => Free.Forever(F))
}

/**
 * FreePure - A pure value in the Free monad.
 */
class FreePure extends Free {
    __New(Value) {
        this._value := Value
    }

    /**
     * Extract the pure value.
     */
    Value => this._value

    /**
     * Check if this is a pure value.
     */
    IsPure => true

    /**
     * Map over the value.
     */
    Map(Fn) => Free.Pure(Fn(this._value))

    /**
     * Monadic bind.
     */
    FlatMap(Fn) => Fn(this._value)

    /**
     * Applicative.
     */
    Ap(Other) => Other.Map(this._value)

    /**
     * Interpret this Free monad.
     * For Pure, just return the value.
     */
    Interpret(Interpreter) => this._value

    /**
     * Fold the Free structure.
     */
    Fold(OnPure, OnSuspend) => OnPure(this._value)

    /**
     * Run with natural transformation to another monad.
     */
    FoldMap(Transform) => this._value

    ToString() => "Free.Pure(" . String(this._value) . ")"
}

/**
 * FreeSuspend - A suspended effect in the Free monad.
 */
class FreeSuspend extends Free {
    __New(Effect) {
        this._effect := Effect
    }

    /**
     * Get the suspended effect.
     */
    Effect => this._effect

    /**
     * Check if this is pure.
     */
    IsPure => false

    /**
     * Map over the eventual value.
     */
    Map(Fn) {
        ; Map over the continuation
        Mapped := this._effect.Clone()
        OrigNext := this._effect.next
        Mapped.next := (X) => OrigNext(X).Map(Fn)
        return Free.Suspend(Mapped)
    }

    /**
     * Monadic bind.
     */
    FlatMap(Fn) {
        ; Compose with the continuation
        Mapped := this._effect.Clone()
        OrigNext := this._effect.next
        Mapped.next := (X) => OrigNext(X).FlatMap(Fn)
        return Free.Suspend(Mapped)
    }

    /**
     * Applicative.
     */
    Ap(Other) => this.FlatMap((Fn) => Other.Map(Fn))

    /**
     * Interpret this Free monad.
     *
     * The interpreter receives each effect and returns the next Free.
     *
     * @param   {Func}  Interpreter  (Effect) => Free
     * @returns {Any}
     */
    Interpret(Interpreter) {
        Next := Interpreter(this._effect)
        return Next.Interpret(Interpreter)
    }

    /**
     * Fold the Free structure.
     */
    Fold(OnPure, OnSuspend) => OnSuspend(this._effect)

    /**
     * Run with natural transformation.
     */
    FoldMap(Transform) {
        return Transform(this._effect).FlatMap((Next) => Next.FoldMap(Transform))
    }

    ToString() => "Free.Suspend(" . (this._effect.Has("op") ? this._effect.op : "...") . ")"
}
;@endregion

;---------------------------------------------------------------------------
;@region Effect DSLs
/**
 * Pre-built effect DSLs for common use cases.
 */

/**
 * Console - Console I/O effect DSL.
 *
 * @example
 * program := Console.Print("Hello")
 *     .FlatMap((*) => Console.ReadLine())
 *     .FlatMap((input) => Console.Print("You said: " . input))
 *
 * ; Run with real interpreter
 * Console.RunReal(program)
 *
 * ; Or test with mock
 * Console.RunMock(program, ["test input"])
 */
class Console {
    /**
     * Print a message to console.
     */
    static Print(Msg) {
        return Free.LiftF({
            op: "ConsolePrint",
            msg: Msg,
            next: (x) => x
        })
    }

    /**
     * Print a line (with newline).
     */
    static PrintLn(Msg) => Console.Print(Msg . "`n")

    /**
     * Read a line from console.
     */
    static ReadLine() {
        return Free.LiftF({
            op: "ConsoleRead",
            next: (x) => x
        })
    }

    /**
     * Real interpreter using MsgBox/InputBox.
     */
    static RunReal(Program) {
        return Program.Interpret((Effect) {
            switch Effect.op {
                case "ConsolePrint":
                    MsgBox(Effect.msg)
                    return Effect.next("")
                case "ConsoleRead":
                    return Effect.next(InputBox("Input").Value)
                default:
                    throw ValueError("Unknown Console effect: " . Effect.op)
            }
        })
    }

    /**
     * Mock interpreter for testing.
     *
     * @param   {Free}   Program
     * @param   {Array}  Inputs   pre-defined inputs
     * @returns {Object} {result, outputs}
     */
    static RunMock(Program, Inputs := []) {
        Outputs := []
        InputIdx := 1

        Result := Program.Interpret((Effect) {
            switch Effect.op {
                case "ConsolePrint":
                    Outputs.Push(Effect.msg)
                    return Effect.next("")
                case "ConsoleRead":
                    if (InputIdx > Inputs.Length)
                        throw ValueError("Not enough mock inputs")
                    return Effect.next(Inputs[InputIdx++])
                default:
                    throw ValueError("Unknown Console effect: " . Effect.op)
            }
        })

        return {result: Result, outputs: Outputs}
    }
}

/**
 * StateEff - State effect DSL.
 *
 * @example
 * counter := StateEff.Get()
 *     .FlatMap((n) => StateEff.Put(n + 1))
 *     .FlatMap((*) => StateEff.Get())
 *
 * result := StateEff.Run(counter, 0)  ; {value: 1, state: 1}
 */
class StateEff {
    /**
     * Get the current state.
     */
    static Get() {
        return Free.LiftF({
            op: "StateGet",
            next: (x) => x
        })
    }

    /**
     * Set the state.
     */
    static Put(NewState) {
        return Free.LiftF({
            op: "StatePut",
            newState: NewState,
            next: (x) => x
        })
    }

    /**
     * Modify the state with a function.
     */
    static Modify(Fn) {
        return StateEff.Get().FlatMap((S) => StateEff.Put(Fn(S)))
    }

    /**
     * Get a projection of the state.
     */
    static Gets(Fn) {
        return StateEff.Get().Map(Fn)
    }

    /**
     * Run a stateful program.
     *
     * @param   {Free}  Program
     * @param   {Any}   InitState
     * @returns {Object}  {value, state}
     */
    static Run(Program, InitState) {
        State := InitState

        Value := Program.Interpret((Effect) {
            switch Effect.op {
                case "StateGet":
                    return Effect.next(State)
                case "StatePut":
                    State := Effect.newState
                    return Effect.next("")
                default:
                    throw ValueError("Unknown State effect: " . Effect.op)
            }
        })

        return {value: Value, state: State}
    }
}

/**
 * ReaderEff - Reader/Environment effect DSL.
 *
 * @example
 * getConfig := ReaderEff.Ask()
 *     .Map((env) => env.config.dbUrl)
 *
 * result := ReaderEff.Run(getConfig, {config: {dbUrl: "localhost"}})
 */
class ReaderEff {
    /**
     * Get the environment.
     */
    static Ask() {
        return Free.LiftF({
            op: "ReaderAsk",
            next: (x) => x
        })
    }

    /**
     * Get a projection of the environment.
     */
    static Asks(Fn) {
        return ReaderEff.Ask().Map(Fn)
    }

    /**
     * Run with a locally modified environment.
     */
    static Local(ModifyFn, Program) {
        return Free.LiftF({
            op: "ReaderLocal",
            modify: ModifyFn,
            program: Program,
            next: (x) => x
        })
    }

    /**
     * Run a reader program.
     *
     * @param   {Free}  Program
     * @param   {Any}   Env
     * @returns {Any}
     */
    static Run(Program, Env) {
        return Program.Interpret((Effect) {
            switch Effect.op {
                case "ReaderAsk":
                    return Effect.next(Env)
                case "ReaderLocal":
                    LocalEnv := Effect.modify(Env)
                    LocalResult := ReaderEff.Run(Effect.program, LocalEnv)
                    return Effect.next(LocalResult)
                default:
                    throw ValueError("Unknown Reader effect: " . Effect.op)
            }
        })
    }
}

/**
 * WriterEff - Writer/Logging effect DSL.
 *
 * @example
 * logged := WriterEff.Tell("Starting...")
 *     .FlatMap((*) => Free.Pure(42))
 *     .FlatMap((x) => WriterEff.Tell("Got " . x).Map((*) => x))
 *
 * result := WriterEff.Run(logged)  ; {value: 42, log: ["Starting...", "Got 42"]}
 */
class WriterEff {
    /**
     * Write to the log.
     */
    static Tell(Entry) {
        return Free.LiftF({
            op: "WriterTell",
            entry: Entry,
            next: (x) => x
        })
    }

    /**
     * Log multiple entries.
     */
    static TellAll(Entries*) {
        if (Entries.Length = 0)
            return Free.Pure("")
        Result := WriterEff.Tell(Entries[1])
        Loop Entries.Length - 1
            Result := Result.FlatMap((*) => WriterEff.Tell(Entries[A_Index + 1]))
        return Result
    }

    /**
     * Run a writer program.
     *
     * @param   {Free}  Program
     * @returns {Object}  {value, log}
     */
    static Run(Program) {
        Log := []

        Value := Program.Interpret((Effect) {
            switch Effect.op {
                case "WriterTell":
                    Log.Push(Effect.entry)
                    return Effect.next("")
                default:
                    throw ValueError("Unknown Writer effect: " . Effect.op)
            }
        })

        return {value: Value, log: Log}
    }
}

/**
 * ExceptEff - Exception/Error effect DSL.
 *
 * @example
 * safeDivide := (a, b) => b = 0
 *     ? ExceptEff.Throw(Error("Division by zero"))
 *     : Free.Pure(a / b)
 *
 * result := ExceptEff.Run(safeDivide(10, 0))  ; {success: false, error: Error}
 */
class ExceptEff {
    /**
     * Throw an error.
     */
    static Throw(Err) {
        return Free.LiftF({
            op: "ExceptThrow",
            error: Err,
            next: (*) => ""  ; Never called
        })
    }

    /**
     * Catch errors from a program.
     */
    static Catch(Program, Handler) {
        return Free.LiftF({
            op: "ExceptCatch",
            program: Program,
            handler: Handler,
            next: (x) => x
        })
    }

    /**
     * Run with exception handling.
     *
     * @param   {Free}  Program
     * @returns {Object}  {success, value?, error?}
     */
    static Run(Program) {
        try {
            Value := Program.Interpret((Effect) {
                switch Effect.op {
                    case "ExceptThrow":
                        throw Effect.error
                    case "ExceptCatch":
                        try {
                            Result := ExceptEff.Run(Effect.program)
                            if (Result.success)
                                return Effect.next(Result.value)
                            return Effect.handler(Result.error)
                        }
                    default:
                        throw ValueError("Unknown Except effect: " . Effect.op)
                }
            })
            return {success: true, value: Value}
        } catch as E {
            return {success: false, error: E}
        }
    }
}

/**
 * AsyncEff - Async effect DSL.
 *
 * @example
 * delayed := AsyncEff.Delay(1000)
 *     .FlatMap((*) => Free.Pure("Done!"))
 *
 * AsyncEff.Run(delayed, (result) => MsgBox(result))
 */
class AsyncEff {
    /**
     * Delay execution.
     */
    static Delay(Ms) {
        return Free.LiftF({
            op: "AsyncDelay",
            ms: Ms,
            next: (x) => x
        })
    }

    /**
     * Run an async computation.
     */
    static Async(Fn) {
        return Free.LiftF({
            op: "AsyncRun",
            fn: Fn,
            next: (x) => x
        })
    }

    /**
     * Run async program with callback.
     *
     * @param   {Free}  Program
     * @param   {Func}  OnComplete  callback receiving result
     */
    static Run(Program, OnComplete) {
        AsyncEff._RunStep(Program, OnComplete)
    }

    static _RunStep(Program, OnComplete) {
        if (Program.IsPure) {
            OnComplete(Program.Value)
            return
        }

        Effect := Program.Effect

        switch Effect.op {
            case "AsyncDelay":
                Timer := () => AsyncEff._RunStep(Effect.next(""), OnComplete)
                SetTimer(Timer, -Effect.ms)

            case "AsyncRun":
                Effect.fn((Result) {
                    AsyncEff._RunStep(Effect.next(Result), OnComplete)
                })

            default:
                throw ValueError("Unknown Async effect: " . Effect.op)
        }
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Effect Composition
/**
 * Eff - Effect system combinator.
 *
 * Allows composing multiple effect types.
 */
class Eff {
    /**
     * Create a combined interpreter from multiple handlers.
     *
     * @param   {Map}  Handlers  Map of op -> handler function
     * @returns {Func}
     */
    static Interpreter(Handlers) {
        return (Effect) {
            if (Handlers.Has(Effect.op))
                return Handlers[Effect.op](Effect)
            throw ValueError("Unhandled effect: " . Effect.op)
        }
    }

    /**
     * Combine multiple handlers.
     *
     * @param   {Object*}  Handlers
     * @returns {Map}
     */
    static Handlers(HandlerObjs*) {
        Combined := Map()
        for Handler in HandlerObjs {
            for Op, Fn in Handler.OwnProps()
                Combined[Op] := Fn
        }
        return Combined
    }

    /**
     * Run a program with combined handlers.
     *
     * @param   {Free}    Program
     * @param   {Object}  Handlers
     * @returns {Any}
     */
    static Run(Program, Handlers*) {
        Combined := Eff.Handlers(Handlers*)
        return Program.Interpret(Eff.Interpreter(Combined))
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Extensions
class AquaHotkey_Free extends AquaHotkey {
    class Func {
        /**
         * Lift this function into a Free effect.
         *
         * @returns {Free}
         */
        ToFree() {
            Fn := this
            return Free.LiftF({
                op: "Call",
                fn: Fn,
                next: (x) => x
            })
        }
    }

    class Array {
        /**
         * Traverse this array with a Free-returning function.
         *
         * @param   {Func}  Fn
         * @returns {Free}
         */
        TraverseFree(Fn) => Free.Traverse(this, Fn)

        /**
         * Sequence Free computations in this array.
         *
         * @returns {Free}
         */
        SequenceFree() => Free.Sequence(this*)
    }
}
;@endregion
