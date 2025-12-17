#Requires AutoHotkey v2.1-alpha.16

;@region Lens
/**
 * AquaHotkey - Lens.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Lens.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Lens-based functional optics for immutable deep transformations. Lenses
 * provide composable getters and setters that enable elegant manipulation of
 * nested data structures without mutation.
 *
 * A Lens is a first-class abstraction over a "focus" within a data structure.
 * It combines:
 * - A getter function to extract a value
 * - A setter function to produce a new structure with an updated value
 *
 * @example
 * ; Create lenses for nested access
 * nameLens := Lens.Prop("name")
 * addressLens := Lens.Prop("address")
 * cityLens := Lens.Prop("city")
 *
 * ; Compose lenses to reach nested properties
 * cityOfPerson := addressLens >> cityLens
 *
 * person := {name: "Alice", address: {city: "NYC", zip: "10001"}}
 * newPerson := cityOfPerson.Set(person, "LA")
 * ; person.address.city is still "NYC"
 * ; newPerson.address.city is "LA"
 */
class Lens {
    /**
     * Constructs a new Lens from a getter and setter function.
     *
     * ```ahk
     * Getter(Obj) => FocusedValue
     * Setter(Obj, NewValue) => NewObj
     * ```
     *
     * @param   {Func}  Getter  function to extract focused value
     * @param   {Func}  Setter  function to produce new structure with updated value
     */
    __New(Getter, Setter) {
        this._get := Getter
        this._set := Setter
    }

    /**
     * View the focused value through the lens.
     *
     * @example
     * nameLens := Lens.Prop("name")
     * nameLens.View({name: "Alice"}) ; "Alice"
     *
     * @param   {Object}  Obj  the object to view through
     * @returns {Any}
     */
    View(Obj) => this._get(Obj)

    /**
     * Alias for `View`. Extracts the focused value.
     *
     * @param   {Object}  Obj  the object to extract from
     * @returns {Any}
     */
    Get(Obj) => this._get(Obj)

    /**
     * Set a new value through the lens, returning a new object.
     * The original object is not mutated.
     *
     * @example
     * nameLens := Lens.Prop("name")
     * original := {name: "Alice", age: 30}
     * updated := nameLens.Set(original, "Bob")
     * ; original.name is still "Alice"
     * ; updated.name is "Bob"
     *
     * @param   {Object}  Obj    the object to update
     * @param   {Any}     Value  the new value to set
     * @returns {Object}
     */
    Set(Obj, Value) => this._set(Obj, Value)

    /**
     * Modify the focused value through a transformation function.
     * Returns a new object with the transformed value.
     *
     * @example
     * ageLens := Lens.Prop("age")
     * person := {name: "Alice", age: 30}
     * older := ageLens.Over(person, (x) => x + 1)
     * ; older.age is 31
     *
     * @param   {Object}  Obj  the object to modify
     * @param   {Func}    Fn   transformation function
     * @returns {Object}
     */
    Over(Obj, Fn) => this._set(Obj, Fn(this._get(Obj)))

    /**
     * Compose this lens with another lens to focus deeper.
     * Left-to-right composition: `lens1.Compose(lens2)` focuses through
     * lens1 first, then lens2.
     *
     * @example
     * addressLens := Lens.Prop("address")
     * cityLens := Lens.Prop("city")
     * cityOfAddress := addressLens.Compose(cityLens)
     *
     * @param   {Lens}  Other  the lens to compose with
     * @returns {Lens}
     */
    Compose(Other) => Lens(
        (Obj) => Other._get(this._get(Obj)),
        (Obj, Val) => this._set(Obj, Other._set(this._get(Obj), Val))
    )

    /**
     * Compose this lens with another using the `>>` operator.
     * Enables fluent lens composition syntax.
     *
     * @example
     * personCity := addressLens >> cityLens
     *
     * @param   {Lens}  Other  the lens to compose with
     * @returns {Lens}
     */
    __Shr(Other) => this.Compose(Other)

    /**
     * Create a lens that focuses on an object property.
     *
     * @example
     * nameLens := Lens.Prop("name")
     * nameLens.View({name: "Alice"}) ; "Alice"
     *
     * @param   {String}  Name  property name
     * @returns {Lens}
     */
    static Prop(Name) => Lens(
        (Obj) => Obj.%Name%,
        (Obj, Val) => Lens._CloneWith(Obj, Name, Val)
    )

    /**
     * Create a lens that focuses on a Map key.
     *
     * @example
     * keyLens := Lens.Key("foo")
     * keyLens.View(Map("foo", 42)) ; 42
     *
     * @param   {Any}  Key  the map key to focus on
     * @returns {Lens}
     */
    static Key(Key) => Lens(
        (M) => M.Get(Key, ""),
        (M, Val) => Lens._CloneMapWith(M, Key, Val)
    )

    /**
     * Create a lens that focuses on an array index.
     * Uses 1-based indexing consistent with AHK conventions.
     *
     * @example
     * firstLens := Lens.Index(1)
     * firstLens.View([10, 20, 30]) ; 10
     *
     * @param   {Integer}  I  the 1-based index
     * @returns {Lens}
     */
    static Index(I) => Lens(
        (Arr) => Arr[I],
        (Arr, Val) => Lens._CloneArrayWith(Arr, I, Val)
    )

    /**
     * Create an identity lens that focuses on the whole object.
     *
     * @returns {Lens}
     */
    static Identity() => Lens((x) => x, (_, v) => v)

    /**
     * Create an optional lens that handles missing properties gracefully.
     * Returns a default value if the property doesn't exist.
     *
     * @param   {String}  Name     property name
     * @param   {Any}     Default  default value if missing
     * @returns {Lens}
     */
    static PropOr(Name, Default := "") => Lens(
        (Obj) {
            try return Obj.%Name%
            return Default
        },
        (Obj, Val) => Lens._CloneWith(Obj, Name, Val)
    )

    /**
     * Create a lens for the first element of an array.
     * @returns {Lens}
     */
    static First() => Lens.Index(1)

    /**
     * Create a lens for the last element of an array.
     * @returns {Lens}
     */
    static Last() => Lens(
        (Arr) => Arr[Arr.Length],
        (Arr, Val) => Lens._CloneArrayWith(Arr, Arr.Length, Val)
    )

    ;---------------------------------------------------------------------------
    ; Internal helpers for immutable cloning

    static _CloneWith(Obj, Prop, Val) {
        Clone := {}
        for K in Obj.OwnProps()
            Clone.%K% := Obj.%K%
        Clone.%Prop% := Val
        return Clone
    }

    static _CloneMapWith(M, Key, Val) {
        Clone := Map()
        Clone.CaseSense := M.CaseSense
        Clone.Default := M.Default
        for K, V in M
            Clone[K] := V
        Clone[Key] := Val
        return Clone
    }

    static _CloneArrayWith(Arr, I, Val) {
        Clone := Arr.Clone()
        Clone[I] := Val
        return Clone
    }
}
;@endregion

;@region Prism
/**
 * Prism - An optic for sum types (variants/discriminated unions).
 *
 * While a Lens always succeeds in focusing on a value, a Prism may fail
 * because the variant might not match. Perfect for working with Optional,
 * Result/Either types, or any algebraic data type.
 *
 * @example
 * ; Prism for the "Some" case of an Optional
 * somePrism := Prism(
 *     (opt) => opt.IsPresent ? Optional(opt.Value) : Optional(),
 *     (val) => Optional(val)
 * )
 */
class Prism {
    /**
     * Constructs a new Prism.
     *
     * ```ahk
     * Match(Obj) => Optional  ; Returns Optional containing focused value
     * Build(Val) => Obj       ; Constructs a new object from a value
     * ```
     *
     * @param   {Func}  Match  attempts to extract the focused value
     * @param   {Func}  Build  constructs a new instance from a value
     */
    __New(Match, Build) {
        this._match := Match
        this._build := Build
    }

    /**
     * Attempt to extract the focused value.
     * Returns an Optional that may be empty if the prism doesn't match.
     *
     * @param   {Any}  Obj  the object to preview
     * @returns {Optional}
     */
    Preview(Obj) => this._match(Obj)

    /**
     * Construct a new value using this prism's constructor.
     *
     * @param   {Any}  Val  the value to wrap
     * @returns {Any}
     */
    Review(Val) => this._build(Val)

    /**
     * Modify the focused value if the prism matches.
     * Returns the original object unchanged if it doesn't match.
     *
     * @param   {Any}   Obj  the object to modify
     * @param   {Func}  Fn   transformation function
     * @returns {Any}
     */
    Over(Obj, Fn) {
        Matched := this._match(Obj)
        if (!Matched.IsPresent)
            return Obj
        return this._build(Fn(Matched.Value))
    }

    /**
     * Compose this prism with another prism.
     *
     * @param   {Prism}  Other  the prism to compose with
     * @returns {Prism}
     */
    Compose(Other) => Prism(
        (Obj) {
            Outer := this._match(Obj)
            if (!Outer.IsPresent)
                return Optional()
            return Other._match(Outer.Value)
        },
        (Val) => this._build(Other._build(Val))
    )

    /**
     * Compose using `>>` operator.
     * @param   {Prism}  Other
     * @returns {Prism}
     */
    __Shr(Other) => this.Compose(Other)

    /**
     * Create a prism for Optional's Some case.
     * @returns {Prism}
     */
    static Some() => Prism(
        (Opt) => Opt.IsPresent ? Optional(Opt.Value) : Optional(),
        (Val) => Optional(Val)
    )

    /**
     * Create a prism for TryOp's Success case.
     * @returns {Prism}
     */
    static Success() => Prism(
        (Try) => Try.Succeeded ? Optional(Try.Value) : Optional(),
        (Val) => TryOp.Value(Val)
    )

    /**
     * Create a prism for TryOp's Failure case.
     * @returns {Prism}
     */
    static Failure() => Prism(
        (Try) => Try.Failed ? Optional(Try.Value) : Optional(),
        (Err) => TryOp.Failure(Err)
    )
}
;@endregion

;@region Iso
/**
 * Iso (Isomorphism) - A bidirectional transformation.
 *
 * An Iso represents a lossless, reversible transformation between two types.
 * `forward . backward = identity` and `backward . forward = identity`
 *
 * @example
 * ; Celsius to Fahrenheit isomorphism
 * celsiusToFahrenheit := Iso(
 *     (c) => c * 9/5 + 32,
 *     (f) => (f - 32) * 5/9
 * )
 */
class Iso {
    /**
     * Constructs a new Isomorphism.
     *
     * @param   {Func}  Forward   A -> B transformation
     * @param   {Func}  Backward  B -> A transformation
     */
    __New(Forward, Backward) {
        this._forward := Forward
        this._backward := Backward
    }

    /**
     * Apply the forward transformation.
     * @param   {Any}  Val
     * @returns {Any}
     */
    Forward(Val) => this._forward(Val)

    /**
     * Apply the backward transformation.
     * @param   {Any}  Val
     * @returns {Any}
     */
    Backward(Val) => this._backward(Val)

    /**
     * Reverse the isomorphism.
     * @returns {Iso}
     */
    Reverse() => Iso(this._backward, this._forward)

    /**
     * Compose with another isomorphism.
     * @param   {Iso}  Other
     * @returns {Iso}
     */
    Compose(Other) => Iso(
        (x) => Other._forward(this._forward(x)),
        (x) => this._backward(Other._backward(x))
    )

    /**
     * Compose using `>>` operator.
     */
    __Shr(Other) => this.Compose(Other)

    /**
     * Convert this Iso to a Lens.
     * @returns {Lens}
     */
    ToLens() => Lens(this._forward, (_, v) => this._backward(v))

    /**
     * Identity isomorphism.
     * @returns {Iso}
     */
    static Identity() => Iso((x) => x, (x) => x)

    /**
     * String to character array isomorphism.
     * @returns {Iso}
     */
    static StringChars() => Iso(
        (s) => StrSplit(s),
        (arr) {
            result := ""
            for char in arr
                result .= char
            return result
        }
    )

    /**
     * JSON string to object isomorphism (requires Jxon or similar).
     * @returns {Iso}
     */
    static Swapped() => Iso(
        (pair) => [pair[2], pair[1]],
        (pair) => [pair[2], pair[1]]
    )
}
;@endregion

;@region Traversal
/**
 * Traversal - Focus on multiple elements within a structure.
 *
 * While a Lens focuses on exactly one element, a Traversal can focus on
 * zero, one, or many elements. Perfect for operating on all elements
 * of an array or all values of a map.
 *
 * @example
 * ; Modify all elements of an array
 * allElements := Traversal.Each()
 * doubled := allElements.Over([1, 2, 3], (x) => x * 2) ; [2, 4, 6]
 */
class Traversal {
    /**
     * Constructs a new Traversal.
     *
     * ```ahk
     * GetAll(Obj) => Array   ; Returns all focused values
     * ModifyAll(Obj, Fn) => Obj  ; Applies Fn to all focused values
     * ```
     *
     * @param   {Func}  GetAll     extracts all focused values
     * @param   {Func}  ModifyAll  modifies all focused values
     */
    __New(GetAll, ModifyAll) {
        this._getAll := GetAll
        this._modifyAll := ModifyAll
    }

    /**
     * Get all focused values as an array.
     * @param   {Any}  Obj
     * @returns {Array}
     */
    GetAll(Obj) => this._getAll(Obj)

    /**
     * Apply a function to all focused values.
     * @param   {Any}   Obj
     * @param   {Func}  Fn
     * @returns {Any}
     */
    Over(Obj, Fn) => this._modifyAll(Obj, Fn)

    /**
     * Set all focused values to a single value.
     * @param   {Any}  Obj
     * @param   {Any}  Val
     * @returns {Any}
     */
    Set(Obj, Val) => this._modifyAll(Obj, (*) => Val)

    /**
     * Compose with a Lens to traverse then focus.
     * @param   {Lens}  L
     * @returns {Traversal}
     */
    ComposeLens(L) => Traversal(
        (Obj) {
            Result := []
            for Item in this._getAll(Obj)
                Result.Push(L.View(Item))
            return Result
        },
        (Obj, Fn) => this._modifyAll(Obj, (Item) => L.Over(Item, Fn))
    )

    /**
     * Create a traversal for all array elements.
     * @returns {Traversal}
     */
    static Each() => Traversal(
        (Arr) => Arr.Clone(),
        (Arr, Fn) {
            Result := []
            for Item in Arr
                Result.Push(Fn(Item))
            return Result
        }
    )

    /**
     * Create a traversal for all Map values.
     * @returns {Traversal}
     */
    static Values() => Traversal(
        (M) {
            Result := []
            for _, V in M
                Result.Push(V)
            return Result
        },
        (M, Fn) {
            Result := Map()
            Result.CaseSense := M.CaseSense
            for K, V in M
                Result[K] := Fn(V)
            return Result
        }
    )

    /**
     * Create a traversal that filters elements by a predicate.
     * @param   {Func}  Pred  predicate function
     * @returns {Traversal}
     */
    static Filtered(Pred) => Traversal(
        (Arr) {
            Result := []
            for Item in Arr
                if Pred(Item)
                    Result.Push(Item)
            return Result
        },
        (Arr, Fn) {
            Result := []
            for Item in Arr
                Result.Push(Pred(Item) ? Fn(Item) : Item)
            return Result
        }
    )
}
;@endregion

;@region Extensions
class AquaHotkey_Lens extends AquaHotkey {
    class Object {
        /**
         * Create a lens focusing on a property of this object.
         *
         * @example
         * person := {name: "Alice", age: 30}
         * nameLens := person.LensAt("name")
         *
         * @param   {String}  PropName  property name
         * @returns {Lens}
         */
        LensAt(PropName) => Lens.Prop(PropName)

        /**
         * View this object through a lens.
         *
         * @param   {Lens}  L  the lens to view through
         * @returns {Any}
         */
        ViewThrough(L) => L.View(this)

        /**
         * Update this object through a lens (returns new object).
         *
         * @param   {Lens}  L    the lens to update through
         * @param   {Any}   Val  the new value
         * @returns {Object}
         */
        SetThrough(L, Val) => L.Set(this, Val)

        /**
         * Modify this object through a lens (returns new object).
         *
         * @param   {Lens}  L   the lens to modify through
         * @param   {Func}  Fn  transformation function
         * @returns {Object}
         */
        OverThrough(L, Fn) => L.Over(this, Fn)
    }

    class Array {
        /**
         * Create a lens focusing on an index of this array.
         *
         * @param   {Integer}  I  1-based index
         * @returns {Lens}
         */
        LensAt(I) => Lens.Index(I)

        /**
         * Create a traversal over all elements.
         * @returns {Traversal}
         */
        Traverse() => Traversal.Each()
    }

    class Map {
        /**
         * Create a lens focusing on a key of this map.
         *
         * @param   {Any}  Key
         * @returns {Lens}
         */
        LensAt(Key) => Lens.Key(Key)

        /**
         * Create a traversal over all values.
         * @returns {Traversal}
         */
        TraverseValues() => Traversal.Values()
    }
}
;@endregion
