#Requires AutoHotkey v2.1-alpha.16

;@region TypeClass
/**
 * AquaHotkey - TypeClass.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/TypeClass.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Type classes provide Haskell-style ad-hoc polymorphism for AHK. They allow
 * defining generic operations that work differently for different types while
 * maintaining a consistent interface.
 *
 * This enables:
 * - Generic programming (one function works on many types)
 * - Lawful abstractions (Functor, Applicative, Monad, etc.)
 * - Clean separation of interface from implementation
 * - Composable type-level programming
 *
 * @example
 * ; Register Functor instance for Array
 * TC.Register("Functor", "Array", {
 *     Map: (arr, fn) {
 *         result := []
 *         for item in arr
 *             result.Push(fn(item))
 *         return result
 *     }
 * })
 *
 * ; Now use generic fmap on any Functor
 * doubled := TC.fmap([1, 2, 3], (x) => x * 2)  ; [2, 4, 6]
 */
class TC {
    /**
     * Registry of type class instances.
     * Key format: "TypeClass:Type"
     */
    static _instances := Map()

    /**
     * Registry of type class definitions.
     */
    static _classes := Map()

    ;---------------------------------------------------------------------------
    ; Registration API
    ;---------------------------------------------------------------------------

    /**
     * Define a new type class.
     *
     * @example
     * TC.Define("Functor", {
     *     required: ["Map"],
     *     laws: {
     *         identity: (fa) => TC.fmap(fa, (x) => x) == fa,
     *         composition: (fa, f, g) => TC.fmap(TC.fmap(fa, f), g)
     *                                 == TC.fmap(fa, (x) => g(f(x)))
     *     }
     * })
     *
     * @param   {String}  Name    type class name
     * @param   {Object}  Def     definition {required, defaults?, laws?}
     */
    static Define(Name, Def) {
        TC._classes[Name] := Def
    }

    /**
     * Register a type class instance for a type.
     *
     * @example
     * TC.Register("Functor", "Array", {
     *     Map: (arr, fn) => arr.Map(fn)
     * })
     *
     * @param   {String}  TypeClass  type class name
     * @param   {String}  ForType    type name
     * @param   {Object}  Impl       implementation object
     */
    static Register(TypeClass, ForType, Impl) {
        ; Validate required methods if type class is defined
        if (TC._classes.Has(TypeClass)) {
            Def := TC._classes[TypeClass]
            if (Def.Has("required")) {
                for Method in Def.required {
                    if (!Impl.Has(Method))
                        throw ValueError("Instance of " . TypeClass
                            . " for " . ForType
                            . " missing required method: " . Method)
                }
            }
            ; Apply defaults
            if (Def.Has("defaults")) {
                for Method, Default in Def.defaults.OwnProps() {
                    if (!Impl.Has(Method))
                        Impl[Method] := Default
                }
            }
        }

        Key := TypeClass . ":" . ForType
        TC._instances[Key] := Impl
    }

    /**
     * Get instance of type class for a type.
     *
     * @param   {String}  TypeClass  type class name
     * @param   {String}  ForType    type name
     * @returns {Object}
     */
    static Get(TypeClass, ForType) {
        Key := TypeClass . ":" . ForType
        if (TC._instances.Has(Key))
            return TC._instances[Key]
        throw ValueError("No instance of " . TypeClass . " for " . ForType)
    }

    /**
     * Check if instance exists.
     *
     * @param   {String}  TypeClass
     * @param   {String}  ForType
     * @returns {Boolean}
     */
    static Has(TypeClass, ForType) {
        Key := TypeClass . ":" . ForType
        return TC._instances.Has(Key)
    }

    /**
     * Get instance for a value's type.
     *
     * @param   {String}  TypeClass
     * @param   {Any}     Value
     * @returns {Object}
     */
    static For(TypeClass, Value) {
        return TC.Get(TypeClass, Type(Value))
    }

    /**
     * Derive an instance automatically.
     *
     * @param   {String}  TypeClass
     * @param   {String}  ForType
     */
    static Derive(TypeClass, ForType) {
        Impl := TC._AutoDerive(TypeClass, ForType)
        TC.Register(TypeClass, ForType, Impl)
    }

    static _AutoDerive(TypeClass, ForType) {
        switch TypeClass {
            case "Show":
                return {
                    Show: (X) {
                        if (X is String)
                            return '"' . X . '"'
                        if (X is Number)
                            return String(X)
                        if (X is Array) {
                            Parts := []
                            for Item in X
                                Parts.Push(TC.show(Item))
                            return "[" . TC._Join(Parts, ", ") . "]"
                        }
                        return Type(X) . "(" . TC._ShowFields(X) . ")"
                    }
                }

            case "Eq":
                return {
                    Eq: (A, B) => TC._DeepEq(A, B),
                    Neq: (A, B) => !TC._DeepEq(A, B)
                }

            case "Ord":
                return {
                    Compare: (A, B) => TC._DefaultCompare(A, B),
                    Lt: (A, B) => TC._DefaultCompare(A, B) < 0,
                    Le: (A, B) => TC._DefaultCompare(A, B) <= 0,
                    Gt: (A, B) => TC._DefaultCompare(A, B) > 0,
                    Ge: (A, B) => TC._DefaultCompare(A, B) >= 0
                }

            case "Semigroup":
                return {
                    Append: (A, B) {
                        if (A is Array)
                            return [A*, B*]
                        if (A is String)
                            return A . B
                        if (A is Number)
                            return A + B
                        throw ValueError("Cannot derive Semigroup.Append")
                    }
                }

            case "Monoid":
                return {
                    Empty: () {
                        switch ForType {
                            case "Array": return []
                            case "String": return ""
                            case "Integer", "Float", "Number": return 0
                            default: throw ValueError("Cannot derive Monoid.Empty")
                        }
                    },
                    Append: (A, B) => TC.For("Semigroup", A).Append(A, B)
                }

            default:
                throw ValueError("Cannot auto-derive " . TypeClass)
        }
    }

    static _ShowFields(X) {
        Parts := []
        for K in X.OwnProps()
            Parts.Push(K . ": " . TC.show(X.%K%))
        return TC._Join(Parts, ", ")
    }

    static _DeepEq(A, B) {
        if (Type(A) != Type(B))
            return false
        if (!IsObject(A))
            return A = B
        if (A is Array) {
            if (A.Length != B.Length)
                return false
            for I, V in A {
                if (!TC._DeepEq(V, B[I]))
                    return false
            }
            return true
        }
        for K in A.OwnProps() {
            if (!B.HasProp(K))
                return false
            if (!TC._DeepEq(A.%K%, B.%K%))
                return false
        }
        return true
    }

    static _DefaultCompare(A, B) {
        if (A < B) return -1
        if (A > B) return 1
        return 0
    }

    static _Join(Arr, Sep) {
        if (Arr.Length = 0)
            return ""
        Result := Arr[1]
        Loop Arr.Length - 1
            Result .= Sep . Arr[A_Index + 1]
        return Result
    }

    ;---------------------------------------------------------------------------
    ; Generic Functions
    ;---------------------------------------------------------------------------

    ; Functor
    static fmap(Fa, Fn) => TC.For("Functor", Fa).Map(Fa, Fn)

    ; Applicative
    static pure(Type, Val) => TC.Get("Applicative", Type).Pure(Val)
    static ap(Ff, Fa) => TC.For("Applicative", Ff).Ap(Ff, Fa)
    static liftA2(Fn, Fa, Fb) => TC.For("Applicative", Fa).LiftA2(Fn, Fa, Fb)

    ; Monad
    static bind(Ma, Fn) => TC.For("Monad", Ma).Bind(Ma, Fn)
    static join(Mma) => TC.For("Monad", Mma).Join(Mma)
    static return_(Type, Val) => TC.Get("Monad", Type).Return(Val)

    ; Foldable
    static foldr(Fn, Init, Fa) => TC.For("Foldable", Fa).Foldr(Fn, Init, Fa)
    static foldl(Fn, Init, Fa) => TC.For("Foldable", Fa).Foldl(Fn, Init, Fa)
    static foldMap(Fn, Fa) => TC.For("Foldable", Fa).FoldMap(Fn, Fa)

    ; Traversable
    static traverse(Fn, Ta) => TC.For("Traversable", Ta).Traverse(Fn, Ta)
    static sequence(Tma) => TC.For("Traversable", Tma).Sequence(Tma)

    ; Semigroup
    static append(A, B) => TC.For("Semigroup", A).Append(A, B)
    static concat(Items*) {
        if (Items.Length = 0)
            throw ValueError("concat requires at least one argument")
        Result := Items[1]
        Loop Items.Length - 1
            Result := TC.append(Result, Items[A_Index + 1])
        return Result
    }

    ; Monoid
    static empty(Type) => TC.Get("Monoid", Type).Empty()
    static mconcat(Type, Items) {
        E := TC.empty(Type)
        for Item in Items
            E := TC.append(E, Item)
        return E
    }

    ; Show
    static show(X) => TC.For("Show", X).Show(X)

    ; Eq
    static eq(A, B) => TC.For("Eq", A).Eq(A, B)
    static neq(A, B) => TC.For("Eq", A).Neq(A, B)

    ; Ord
    static compare(A, B) => TC.For("Ord", A).Compare(A, B)
    static lt(A, B) => TC.For("Ord", A).Lt(A, B)
    static le(A, B) => TC.For("Ord", A).Le(A, B)
    static gt(A, B) => TC.For("Ord", A).Gt(A, B)
    static ge(A, B) => TC.For("Ord", A).Ge(A, B)
    static min_(A, B) => TC.lt(A, B) ? A : B
    static max_(A, B) => TC.gt(A, B) ? A : B
}
;@endregion

;---------------------------------------------------------------------------
;@region Built-in Type Class Definitions
/**
 * Define standard type classes.
 */
class TypeClassDefinitions {
    static __New() {
        ; Functor: structure-preserving map
        TC.Define("Functor", {
            required: ["Map"]
        })

        ; Applicative: functor with application
        TC.Define("Applicative", {
            required: ["Pure", "Ap"],
            defaults: {
                LiftA2: (Fn, Fa, Fb) {
                    FnF := TC.fmap(Fa, (A) => (B) => Fn(A, B))
                    return TC.ap(FnF, Fb)
                }
            }
        })

        ; Monad: applicative with bind
        TC.Define("Monad", {
            required: ["Return", "Bind"],
            defaults: {
                Join: (Mma) => TC.bind(Mma, (x) => x)
            }
        })

        ; Foldable: reducible structures
        TC.Define("Foldable", {
            required: ["Foldr"]
        })

        ; Traversable: traversable structures
        TC.Define("Traversable", {
            required: ["Traverse"]
        })

        ; Semigroup: types with associative append
        TC.Define("Semigroup", {
            required: ["Append"]
        })

        ; Monoid: semigroup with identity
        TC.Define("Monoid", {
            required: ["Empty", "Append"]
        })

        ; Show: printable types
        TC.Define("Show", {
            required: ["Show"]
        })

        ; Eq: equality testable types
        TC.Define("Eq", {
            required: ["Eq"],
            defaults: {
                Neq: (A, B) => !TC.eq(A, B)
            }
        })

        ; Ord: orderable types
        TC.Define("Ord", {
            required: ["Compare"],
            defaults: {
                Lt: (A, B) => TC.compare(A, B) < 0,
                Le: (A, B) => TC.compare(A, B) <= 0,
                Gt: (A, B) => TC.compare(A, B) > 0,
                Ge: (A, B) => TC.compare(A, B) >= 0
            }
        })
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Built-in Instances
/**
 * Register instances for built-in types.
 */
class BuiltinInstances {
    static __New() {
        ;-----------------------------------------------------------------------
        ; Array instances
        ;-----------------------------------------------------------------------
        TC.Register("Functor", "Array", {
            Map: (Arr, Fn) {
                Result := []
                for Item in Arr
                    Result.Push(Fn(Item))
                return Result
            }
        })

        TC.Register("Applicative", "Array", {
            Pure: (Val) => [Val],
            Ap: (ArrFn, ArrVal) {
                Result := []
                for Fn in ArrFn
                    for Val in ArrVal
                        Result.Push(Fn(Val))
                return Result
            }
        })

        TC.Register("Monad", "Array", {
            Return: (Val) => [Val],
            Bind: (Arr, Fn) {
                Result := []
                for Item in Arr
                    for Sub in Fn(Item)
                        Result.Push(Sub)
                return Result
            }
        })

        TC.Register("Foldable", "Array", {
            Foldr: (Fn, Init, Arr) {
                Acc := Init
                Loop Arr.Length
                    Acc := Fn(Arr[Arr.Length - A_Index + 1], Acc)
                return Acc
            },
            Foldl: (Fn, Init, Arr) {
                Acc := Init
                for Item in Arr
                    Acc := Fn(Acc, Item)
                return Acc
            }
        })

        TC.Register("Semigroup", "Array", {
            Append: (A, B) => [A*, B*]
        })

        TC.Register("Monoid", "Array", {
            Empty: () => [],
            Append: (A, B) => [A*, B*]
        })

        TC.Register("Show", "Array", {
            Show: (Arr) {
                Parts := []
                for Item in Arr
                    Parts.Push(TC.show(Item))
                return "[" . TC._Join(Parts, ", ") . "]"
            }
        })

        TC.Register("Eq", "Array", {
            Eq: (A, B) => TC._DeepEq(A, B)
        })

        ;-----------------------------------------------------------------------
        ; String instances
        ;-----------------------------------------------------------------------
        TC.Register("Semigroup", "String", {
            Append: (A, B) => A . B
        })

        TC.Register("Monoid", "String", {
            Empty: () => "",
            Append: (A, B) => A . B
        })

        TC.Register("Show", "String", {
            Show: (S) => '"' . S . '"'
        })

        TC.Register("Eq", "String", {
            Eq: (A, B) => A = B
        })

        TC.Register("Ord", "String", {
            Compare: (A, B) => StrCompare(A, B)
        })

        ;-----------------------------------------------------------------------
        ; Integer instances
        ;-----------------------------------------------------------------------
        TC.Register("Show", "Integer", {
            Show: (N) => String(N)
        })

        TC.Register("Eq", "Integer", {
            Eq: (A, B) => A = B
        })

        TC.Register("Ord", "Integer", {
            Compare: (A, B) => A < B ? -1 : A > B ? 1 : 0
        })

        TC.Register("Semigroup", "Integer", {
            Append: (A, B) => A + B  ; Additive semigroup
        })

        TC.Register("Monoid", "Integer", {
            Empty: () => 0,
            Append: (A, B) => A + B
        })

        ;-----------------------------------------------------------------------
        ; Float instances
        ;-----------------------------------------------------------------------
        TC.Register("Show", "Float", {
            Show: (N) => String(N)
        })

        TC.Register("Eq", "Float", {
            Eq: (A, B) => A = B
        })

        TC.Register("Ord", "Float", {
            Compare: (A, B) => A < B ? -1 : A > B ? 1 : 0
        })

        ;-----------------------------------------------------------------------
        ; Map instances
        ;-----------------------------------------------------------------------
        TC.Register("Functor", "Map", {
            Map: (M, Fn) {
                Result := Map()
                Result.CaseSense := M.CaseSense
                for K, V in M
                    Result[K] := Fn(V)
                return Result
            }
        })

        TC.Register("Foldable", "Map", {
            Foldr: (Fn, Init, M) {
                Acc := Init
                Entries := []
                for K, V in M
                    Entries.Push([K, V])
                Loop Entries.Length
                    Acc := Fn(Entries[Entries.Length - A_Index + 1][2], Acc)
                return Acc
            },
            Foldl: (Fn, Init, M) {
                Acc := Init
                for K, V in M
                    Acc := Fn(Acc, V)
                return Acc
            }
        })

        TC.Register("Show", "Map", {
            Show: (M) {
                Parts := []
                for K, V in M
                    Parts.Push(TC.show(K) . ": " . TC.show(V))
                return "Map{" . TC._Join(Parts, ", ") . "}"
            }
        })

        ;-----------------------------------------------------------------------
        ; Optional instances (if available)
        ;-----------------------------------------------------------------------
        TC.Register("Functor", "Optional", {
            Map: (Opt, Fn) {
                if (Opt.IsAbsent)
                    return Opt
                return Optional(Fn(Opt.Value))
            }
        })

        TC.Register("Applicative", "Optional", {
            Pure: (Val) => Optional(Val),
            Ap: (OptFn, OptVal) {
                if (OptFn.IsAbsent || OptVal.IsAbsent)
                    return Optional()
                return Optional(OptFn.Value(OptVal.Value))
            }
        })

        TC.Register("Monad", "Optional", {
            Return: (Val) => Optional(Val),
            Bind: (Opt, Fn) {
                if (Opt.IsAbsent)
                    return Opt
                return Fn(Opt.Value)
            }
        })

        TC.Register("Show", "Optional", {
            Show: (Opt) {
                if (Opt.IsAbsent)
                    return "Optional.Empty()"
                return "Optional(" . TC.show(Opt.Value) . ")"
            }
        })
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Constraint
/**
 * Constraint - Type class constraint checking.
 *
 * Allows requiring that a type implement specific type classes.
 *
 * @example
 * ; Function that requires Ord and Show
 * sortAndPrint(arr) {
 *     Constraint.Require(Type(arr[1]), ["Ord", "Show"])
 *     sorted := arr.Sort((a, b) => TC.compare(a, b))
 *     for item in sorted
 *         OutputDebug(TC.show(item))
 * }
 */
class Constraint {
    /**
     * Require that a type implement specific type classes.
     *
     * @param   {String}  ForType     type name
     * @param   {Array}   TypeClasses required type classes
     */
    static Require(ForType, TypeClasses) {
        Missing := []
        for TC_ in TypeClasses {
            if (!TC.Has(TC_, ForType))
                Missing.Push(TC_)
        }
        if (Missing.Length > 0)
            throw ValueError(ForType . " does not implement: "
                . TC._Join(Missing, ", "))
    }

    /**
     * Check if type satisfies constraints (without throwing).
     *
     * @param   {String}  ForType
     * @param   {Array}   TypeClasses
     * @returns {Boolean}
     */
    static Satisfies(ForType, TypeClasses) {
        for TC_ in TypeClasses {
            if (!TC.Has(TC_, ForType))
                return false
        }
        return true
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Generic
/**
 * Generic - Higher-level generic programming utilities.
 *
 * @example
 * ; Generic sorting for any Ord instance
 * sorted := Generic.Sort([3, 1, 4, 1, 5], "Integer")
 *
 * ; Generic equality check
 * equal := Generic.Equals([1, 2, 3], [1, 2, 3])
 */
class Generic {
    /**
     * Sort using Ord instance.
     *
     * @param   {Array}   Arr
     * @param   {String}  ElementType
     * @returns {Array}
     */
    static Sort(Arr, ElementType?) {
        if (!IsSet(ElementType) && Arr.Length > 0)
            ElementType := Type(Arr[1])

        Constraint.Require(ElementType, ["Ord"])

        ; Simple insertion sort for demonstration
        Result := Arr.Clone()
        Loop Result.Length - 1 {
            I := A_Index
            J := I + 1
            while (J > 1 && TC.gt(Result[J - 1], Result[J])) {
                Temp := Result[J - 1]
                Result[J - 1] := Result[J]
                Result[J] := Temp
                J--
            }
        }
        return Result
    }

    /**
     * Generic equality using Eq instance.
     */
    static Equals(A, B) => TC.eq(A, B)

    /**
     * Generic string conversion using Show instance.
     */
    static ToString(X) => TC.show(X)

    /**
     * Generic map using Functor instance.
     */
    static Map(Fa, Fn) => TC.fmap(Fa, Fn)

    /**
     * Generic flatMap using Monad instance.
     */
    static FlatMap(Ma, Fn) => TC.bind(Ma, Fn)

    /**
     * Generic reduce using Foldable instance.
     */
    static Reduce(Fn, Init, Fa) => TC.foldl(Fn, Init, Fa)

    /**
     * Generic filter (for monads that support it).
     */
    static Filter(Pred, Ma) {
        return TC.bind(Ma, (X) {
            return Pred(X) ? TC.return_(Type(Ma), X) : TC.empty(Type(Ma))
        })
    }

    /**
     * Do-notation simulation using array of functions.
     * Each function receives accumulated values and returns next monad.
     *
     * @example
     * result := Generic.Do("Array", [
     *     () => [1, 2, 3],
     *     (x) => [x, x * 2],
     *     (x, y) => [x + y]
     * ])
     */
    static Do(Type, Steps) {
        if (Steps.Length = 0)
            return TC.pure(Type, "")

        Result := Steps[1]()
        Values := []

        Loop Steps.Length - 1 {
            I := A_Index + 1
            StepFn := Steps[I]
            Result := TC.bind(Result, (V) {
                Values.Push(V)
                return StepFn(Values*)
            })
        }

        return Result
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Extensions
class AquaHotkey_TypeClass extends AquaHotkey {
    class Any {
        /**
         * Show this value using its Show instance.
         *
         * @returns {String}
         */
        TcShow() => TC.show(this)

        /**
         * Check equality using Eq instance.
         *
         * @param   {Any}  Other
         * @returns {Boolean}
         */
        TcEq(Other) => TC.eq(this, Other)

        /**
         * Compare using Ord instance.
         *
         * @param   {Any}  Other
         * @returns {Integer}  -1, 0, or 1
         */
        TcCompare(Other) => TC.compare(this, Other)
    }

    class Array {
        /**
         * Map using Functor instance.
         *
         * @param   {Func}  Fn
         * @returns {Array}
         */
        TcMap(Fn) => TC.fmap(this, Fn)

        /**
         * FlatMap using Monad instance.
         *
         * @param   {Func}  Fn
         * @returns {Array}
         */
        TcBind(Fn) => TC.bind(this, Fn)

        /**
         * Fold right using Foldable instance.
         *
         * @param   {Func}  Fn
         * @param   {Any}   Init
         * @returns {Any}
         */
        TcFoldr(Fn, Init) => TC.foldr(Fn, Init, this)

        /**
         * Fold left using Foldable instance.
         *
         * @param   {Func}  Fn
         * @param   {Any}   Init
         * @returns {Any}
         */
        TcFoldl(Fn, Init) => TC.foldl(Fn, Init, this)

        /**
         * Append using Semigroup instance.
         *
         * @param   {Array}  Other
         * @returns {Array}
         */
        TcAppend(Other) => TC.append(this, Other)
    }
}
;@endregion
