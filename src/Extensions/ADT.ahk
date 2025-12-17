#Requires AutoHotkey v2.1-alpha.16

;@region ADT
/**
 * AquaHotkey - ADT.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/ADT.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Algebraic Data Types (ADTs) via sealed class hierarchies with exhaustive
 * pattern matching. Enables type-safe discriminated unions with compile-time-like
 * safety through runtime validation.
 *
 * ADTs are fundamental to functional programming, allowing you to model data
 * as a fixed set of variants, each potentially carrying different data.
 *
 * @example
 * ; Create a Result type with Ok and Err variants
 * Result := ADT.Sealed(
 *     {name: "Ok",  fields: ["value"]},
 *     {name: "Err", fields: ["error"]}
 * )
 *
 * ; Construct variants
 * success := Result.Ok(42)
 * failure := Result.Err("Something went wrong")
 *
 * ; Pattern match exhaustively
 * message := success.Match(Map(
 *     "Ok",  (r) => "Got: " . r.value,
 *     "Err", (r) => "Error: " . r.error
 * ))
 */
class ADT {
    /**
     * Creates a sealed sum type with the specified variants.
     * The resulting type cannot be extended with new variants at runtime,
     * ensuring exhaustive pattern matching.
     *
     * @example
     * Option := ADT.Sealed(
     *     {name: "Some", fields: ["value"]},
     *     {name: "None", fields: []}
     * )
     *
     * @param   {Object*}  Variants  variant descriptors {name, fields}
     * @returns {Class}
     */
    static Sealed(Variants*) {
        ; Create the sealed base type
        Sealed := Class("ADT.Sealed", Object)
        Sealed._variants := Map()
        Sealed._variantNames := []

        ; Create each variant as a subclass
        for Variant in Variants {
            Name := Variant.name
            Fields := Variant.Has("fields") ? Variant.fields : []

            Sealed._variantNames.Push(Name)
            VariantClass := ADT._CreateVariant(Sealed, Name, Fields)
            Sealed._variants[Name] := VariantClass

            ; Define constructor on sealed type: Result.Ok(value)
            ADT._DefineVariantConstructor(Sealed, Name, VariantClass, Fields)
        }

        ; Add Match method to prototype
        Sealed.Prototype.DefineProp("Match", {
            Call: (this, Cases) => ADT._Match(this, Cases, Sealed._variantNames)
        })

        ; Add MatchPartial for non-exhaustive matching
        Sealed.Prototype.DefineProp("MatchPartial", {
            Call: (this, Cases) => ADT._MatchPartial(this, Cases)
        })

        ; Add variant checking
        Sealed.Prototype.DefineProp("Is", {
            Call: (this, VariantName) => this.__Class = VariantName
        })

        ; Add ToString
        Sealed.Prototype.DefineProp("ToString", {
            Call: (this) => ADT._ToString(this)
        })

        return Sealed
    }

    /**
     * Creates a single variant class.
     */
    static _CreateVariant(Parent, Name, Fields) {
        Variant := Class(Name, Parent)
        Variant._fields := Fields
        Variant._fieldSet := Map()
        for Field in Fields
            Variant._fieldSet[Field] := true

        ; Define __New to set fields
        if (Fields.Length > 0) {
            Variant.Prototype.DefineProp("__New", {
                Call: (this, Values*) {
                    if (Values.Length != Fields.Length)
                        throw ValueError("Expected " . Fields.Length
                            . " arguments, got " . Values.Length)
                    for I, Field in Fields
                        this.DefineProp(Field, {Value: Values[I]})
                }
            })
        }

        ; Define field accessors for destructuring
        Variant.Prototype.DefineProp("Fields", {
            Get: (this) {
                Result := []
                for Field in Fields
                    Result.Push(this.%Field%)
                return Result
            }
        })

        return Variant
    }

    /**
     * Defines a variant constructor on the sealed type.
     */
    static _DefineVariantConstructor(Sealed, Name, VariantClass, Fields) {
        Sealed.DefineProp(Name, {
            Call: (_, Args*) => VariantClass(Args*)
        })
    }

    /**
     * Performs exhaustive pattern matching.
     * Throws if not all variants are covered.
     */
    static _Match(Instance, Cases, VariantNames) {
        ; Check exhaustiveness
        for Name in VariantNames {
            if (!Cases.Has(Name) && !Cases.Has("_"))
                throw ValueError("Non-exhaustive match: missing case for '" . Name . "'")
        }

        TypeName := Instance.__Class
        if (Cases.Has(TypeName))
            return Cases[TypeName](Instance)
        if (Cases.Has("_"))
            return Cases["_"](Instance)

        throw ValueError("Unknown variant: " . TypeName)
    }

    /**
     * Performs partial pattern matching with optional default.
     */
    static _MatchPartial(Instance, Cases) {
        TypeName := Instance.__Class
        if (Cases.Has(TypeName))
            return Optional(Cases[TypeName](Instance))
        if (Cases.Has("_"))
            return Optional(Cases["_"](Instance))
        return Optional()
    }

    /**
     * Generates string representation.
     */
    static _ToString(Instance) {
        TypeName := Instance.__Class
        try {
            Fields := Instance.Fields
            if (Fields.Length = 0)
                return TypeName . "()"

            Parts := []
            for Val in Fields {
                if (Val is String)
                    Parts.Push('"' . Val . '"')
                else
                    Parts.Push(String(Val))
            }
            return TypeName . "(" . Parts.Join(", ") . ")"
        }
        return TypeName . "()"
    }

    ;---------------------------------------------------------------------------
    ; Common ADT Types
    ;---------------------------------------------------------------------------

    /**
     * Creates a Maybe/Option type.
     *
     * @example
     * Maybe := ADT.Maybe()
     * some := Maybe.Just(42)
     * none := Maybe.Nothing()
     *
     * @returns {Class}
     */
    static Maybe() => ADT.Sealed(
        {name: "Just",    fields: ["value"]},
        {name: "Nothing", fields: []}
    )

    /**
     * Creates an Either type for computations that can fail.
     *
     * @example
     * Either := ADT.Either()
     * right := Either.Right(42)
     * left := Either.Left("error")
     *
     * @returns {Class}
     */
    static Either() => ADT.Sealed(
        {name: "Left",  fields: ["value"]},
        {name: "Right", fields: ["value"]}
    )

    /**
     * Creates a Validation type for accumulating errors.
     *
     * @example
     * Validation := ADT.Validation()
     * valid := Validation.Valid(42)
     * invalid := Validation.Invalid(["error1", "error2"])
     *
     * @returns {Class}
     */
    static Validation() => ADT.Sealed(
        {name: "Valid",   fields: ["value"]},
        {name: "Invalid", fields: ["errors"]}
    )

    /**
     * Creates a RemoteData type for async operations.
     *
     * @example
     * RemoteData := ADT.RemoteData()
     * notAsked := RemoteData.NotAsked()
     * loading := RemoteData.Loading()
     * success := RemoteData.Success(data)
     * failure := RemoteData.Failure(error)
     *
     * @returns {Class}
     */
    static RemoteData() => ADT.Sealed(
        {name: "NotAsked", fields: []},
        {name: "Loading",  fields: []},
        {name: "Success",  fields: ["data"]},
        {name: "Failure",  fields: ["error"]}
    )

    /**
     * Creates a List type (cons list).
     *
     * @returns {Class}
     */
    static List() {
        ListType := ADT.Sealed(
            {name: "Cons", fields: ["head", "tail"]},
            {name: "Nil",  fields: []}
        )

        ; Add helper methods
        ListType.From := (Arr*) {
            Result := ListType.Nil()
            Loop Arr.Length
                Result := ListType.Cons(Arr[Arr.Length - A_Index + 1], Result)
            return Result
        }

        ListType.Prototype.DefineProp("ToArray", {
            Call: (this) {
                Result := []
                Current := this
                while (Current.Is("Cons")) {
                    Result.Push(Current.head)
                    Current := Current.tail
                }
                return Result
            }
        })

        ListType.Prototype.DefineProp("Map", {
            Call: (this, Fn) {
                return this.Match(Map(
                    "Nil",  (*) => ListType.Nil(),
                    "Cons", (c) => ListType.Cons(Fn(c.head), c.tail.Map(Fn))
                ))
            }
        })

        ListType.Prototype.DefineProp("FoldL", {
            Call: (this, Fn, Init) {
                Acc := Init
                Current := this
                while (Current.Is("Cons")) {
                    Acc := Fn(Acc, Current.head)
                    Current := Current.tail
                }
                return Acc
            }
        })

        ListType.Prototype.DefineProp("Length", {
            Get: (this) => this.FoldL((acc, _) => acc + 1, 0)
        })

        return ListType
    }

    /**
     * Creates a Tree type (binary tree).
     *
     * @returns {Class}
     */
    static Tree() {
        TreeType := ADT.Sealed(
            {name: "Node",  fields: ["value", "left", "right"]},
            {name: "Empty", fields: []}
        )

        TreeType.Leaf := (Value) => TreeType.Node(Value, TreeType.Empty(), TreeType.Empty())

        TreeType.Prototype.DefineProp("Map", {
            Call: (this, Fn) {
                return this.Match(Map(
                    "Empty", (*) => TreeType.Empty(),
                    "Node", (n) => TreeType.Node(
                        Fn(n.value),
                        n.left.Map(Fn),
                        n.right.Map(Fn)
                    )
                ))
            }
        })

        TreeType.Prototype.DefineProp("FoldL", {
            Call: (this, Fn, Init) {
                return this.Match(Map(
                    "Empty", (*) => Init,
                    "Node", (n) {
                        LeftAcc := n.left.FoldL(Fn, Init)
                        NodeAcc := Fn(LeftAcc, n.value)
                        return n.right.FoldL(Fn, NodeAcc)
                    }
                ))
            }
        })

        TreeType.Prototype.DefineProp("ToArray", {
            Call: (this) => this.FoldL((acc, v) => (acc.Push(v), acc), [])
        })

        return TreeType
    }
}
;@endregion

;@region Pattern
/**
 * Pattern - Advanced pattern matching with guards and extractors.
 *
 * Provides Scala-like pattern matching capabilities beyond simple variant
 * matching, including guards, type checks, and value extraction.
 *
 * @example
 * result := Pattern.Match(value, [
 *     Pattern.When(IsNumber).And((x) => x > 0).Then((x) => "positive: " . x),
 *     Pattern.When(IsNumber).Then((x) => "non-positive: " . x),
 *     Pattern.When((x) => x is String).Then((x) => "string: " . x),
 *     Pattern.Default(() => "unknown")
 * ])
 */
class Pattern {
    /**
     * Execute pattern matching against a list of cases.
     *
     * @param   {Any}    Value  the value to match
     * @param   {Array}  Cases  array of PatternCase objects
     * @returns {Any}
     */
    static Match(Value, Cases) {
        for Case in Cases {
            if (Case._matches(Value))
                return Case._execute(Value)
        }
        throw ValueError("Non-exhaustive pattern match")
    }

    /**
     * Execute pattern matching, returning Optional.
     *
     * @param   {Any}    Value  the value to match
     * @param   {Array}  Cases  array of PatternCase objects
     * @returns {Optional}
     */
    static MatchOpt(Value, Cases) {
        for Case in Cases {
            if (Case._matches(Value))
                return Optional(Case._execute(Value))
        }
        return Optional()
    }

    /**
     * Start building a pattern case with a predicate.
     *
     * @param   {Func}  Pred  predicate function
     * @returns {PatternCase}
     */
    static When(Pred) => PatternCase(Pred)

    /**
     * Create a type-checking pattern.
     *
     * @param   {Class}  Type  the type to check for
     * @returns {PatternCase}
     */
    static IsType(Type) => PatternCase((x) => x is Type)

    /**
     * Create an equality pattern.
     *
     * @param   {Any}  Expected  the value to compare against
     * @returns {PatternCase}
     */
    static Equals(Expected) => PatternCase((x) => x = Expected)

    /**
     * Create a range pattern for numbers.
     *
     * @param   {Number}  Min  minimum value (inclusive)
     * @param   {Number}  Max  maximum value (inclusive)
     * @returns {PatternCase}
     */
    static InRange(Min, Max) => PatternCase((x) => IsNumber(x) && x >= Min && x <= Max)

    /**
     * Create a regex pattern for strings.
     *
     * @param   {String}  Regex  the regex pattern
     * @returns {PatternCase}
     */
    static Matches(Regex) => PatternCase((x) => (x is String) && RegExMatch(x, Regex))

    /**
     * Create a default/catch-all pattern.
     *
     * @param   {Func}  Handler  the handler function
     * @returns {PatternCase}
     */
    static Default(Handler) => PatternCase((*) => true).Then(Handler)

    /**
     * Create a wildcard pattern that matches anything.
     *
     * @returns {PatternCase}
     */
    static Any() => PatternCase((*) => true)

    /**
     * Create a pattern that matches if all sub-patterns match.
     *
     * @param   {PatternCase*}  Patterns  patterns to combine
     * @returns {PatternCase}
     */
    static All(Patterns*) {
        return PatternCase((x) {
            for P in Patterns
                if (!P._matches(x))
                    return false
            return true
        })
    }

    /**
     * Create a pattern that matches if any sub-pattern matches.
     *
     * @param   {PatternCase*}  Patterns  patterns to combine
     * @returns {PatternCase}
     */
    static AnyOf(Patterns*) {
        return PatternCase((x) {
            for P in Patterns
                if (P._matches(x))
                    return true
            return false
        })
    }

    /**
     * Create a pattern for object structure matching.
     *
     * @param   {Object}  Shape  object describing expected shape
     * @returns {PatternCase}
     */
    static Shape(ShapeDesc) {
        return PatternCase((x) {
            if (!IsObject(x))
                return false
            for K, V in ShapeDesc.OwnProps() {
                try {
                    if (V is Func) {
                        if (!V(x.%K%))
                            return false
                    } else {
                        if (x.%K% != V)
                            return false
                    }
                } catch {
                    return false
                }
            }
            return true
        })
    }

    /**
     * Create a pattern for array structure matching.
     *
     * @param   {Array}  ElementPatterns  patterns for each element
     * @returns {PatternCase}
     */
    static ArrayOf(ElementPatterns*) {
        return PatternCase((x) {
            if (!(x is Array) || x.Length != ElementPatterns.Length)
                return false
            for I, P in ElementPatterns {
                if (P is Func) {
                    if (!P(x[I]))
                        return false
                } else if (P is PatternCase) {
                    if (!P._matches(x[I]))
                        return false
                } else {
                    if (x[I] != P)
                        return false
                }
            }
            return true
        })
    }
}

/**
 * PatternCase - A single case in pattern matching.
 */
class PatternCase {
    __New(Pred) {
        this._pred := Pred
        this._guards := []
        this._handler := (x) => x
    }

    /**
     * Add an additional guard condition.
     *
     * @param   {Func}  Guard  guard predicate
     * @returns {PatternCase}
     */
    And(Guard) {
        this._guards.Push(Guard)
        return this
    }

    /**
     * Set the handler function for when this pattern matches.
     *
     * @param   {Func}  Handler  handler function
     * @returns {PatternCase}
     */
    Then(Handler) {
        this._handler := Handler
        return this
    }

    /**
     * Check if this pattern matches a value.
     */
    _matches(Value) {
        if (!this._pred(Value))
            return false
        for Guard in this._guards
            if (!Guard(Value))
                return false
        return true
    }

    /**
     * Execute the handler.
     */
    _execute(Value) => this._handler(Value)
}
;@endregion

;@region Extensions
class AquaHotkey_ADT extends AquaHotkey {
    class Any {
        /**
         * Pattern match this value against cases.
         *
         * @example
         * value.PatternMatch([
         *     Pattern.When(IsNumber).Then((x) => x * 2),
         *     Pattern.Default(() => 0)
         * ])
         *
         * @param   {Array}  Cases
         * @returns {Any}
         */
        PatternMatch(Cases) => Pattern.Match(this, Cases)
    }

    class Array {
        /**
         * Create an ADT List from this array.
         *
         * @returns {ADT.List}
         */
        ToList() {
            ListType := ADT.List()
            return ListType.From(this*)
        }
    }
}
;@endregion
