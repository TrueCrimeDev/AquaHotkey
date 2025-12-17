#Requires AutoHotkey v2.1-alpha.16

;@region Transducer
/**
 * AquaHotkey - Transducer.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Transducer.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Transducers are composable algorithmic transformations that are independent
 * of the context of their input and output sources. They compose directly
 * without creating intermediate collections, providing excellent performance.
 *
 * Unlike traditional map/filter chains that create intermediate arrays,
 * transducers compose the transformations themselves, processing elements
 * one at a time through the entire pipeline.
 *
 * @example
 * ; Traditional approach: creates intermediate arrays
 * result := arr.Filter(isEven).Map(double).Take(5)
 *
 * ; Transducer approach: single pass, no intermediate arrays
 * xform := Xf.Compose(
 *     Xf.Filter((x) => Mod(x, 2) = 0),
 *     Xf.Map((x) => x * 2),
 *     Xf.Take(5)
 * )
 * result := Xf.Into(xform, [1,2,3,4,5,6,7,8,9,10])
 */
class Xf {
    /**
     * Create a mapping transducer.
     *
     * @example
     * xf := Xf.Map((x) => x * 2)
     * Xf.Into(xf, [1, 2, 3]) ; [2, 4, 6]
     *
     * @param   {Func}  Fn  transformation function
     * @returns {Func}
     */
    static Map(Fn) {
        return (Reducer) => (Acc, X) => Reducer(Acc, Fn(X))
    }

    /**
     * Create a filtering transducer.
     *
     * @example
     * xf := Xf.Filter((x) => x > 2)
     * Xf.Into(xf, [1, 2, 3, 4]) ; [3, 4]
     *
     * @param   {Func}  Pred  predicate function
     * @returns {Func}
     */
    static Filter(Pred) {
        return (Reducer) => (Acc, X) => Pred(X) ? Reducer(Acc, X) : Acc
    }

    /**
     * Create a removing (inverse filter) transducer.
     *
     * @param   {Func}  Pred  predicate function
     * @returns {Func}
     */
    static Remove(Pred) {
        return (Reducer) => (Acc, X) => Pred(X) ? Acc : Reducer(Acc, X)
    }

    /**
     * Create a take transducer that limits elements.
     *
     * @example
     * xf := Xf.Take(3)
     * Xf.Into(xf, [1, 2, 3, 4, 5]) ; [1, 2, 3]
     *
     * @param   {Integer}  N  number of elements to take
     * @returns {Func}
     */
    static Take(N) {
        return (Reducer) {
            Count := 0
            return (Acc, X) {
                if (++Count <= N) {
                    Result := Reducer(Acc, X)
                    return Count = N ? Reduced(Result) : Result
                }
                return Reduced(Acc)
            }
        }
    }

    /**
     * Create a take-while transducer.
     *
     * @param   {Func}  Pred  predicate function
     * @returns {Func}
     */
    static TakeWhile(Pred) {
        return (Reducer) => (Acc, X) {
            return Pred(X) ? Reducer(Acc, X) : Reduced(Acc)
        }
    }

    /**
     * Create a drop transducer that skips elements.
     *
     * @example
     * xf := Xf.Drop(2)
     * Xf.Into(xf, [1, 2, 3, 4, 5]) ; [3, 4, 5]
     *
     * @param   {Integer}  N  number of elements to drop
     * @returns {Func}
     */
    static Drop(N) {
        return (Reducer) {
            Count := 0
            return (Acc, X) {
                return ++Count > N ? Reducer(Acc, X) : Acc
            }
        }
    }

    /**
     * Create a drop-while transducer.
     *
     * @param   {Func}  Pred  predicate function
     * @returns {Func}
     */
    static DropWhile(Pred) {
        return (Reducer) {
            Dropping := true
            return (Acc, X) {
                if (Dropping && Pred(X))
                    return Acc
                Dropping := false
                return Reducer(Acc, X)
            }
        }
    }

    /**
     * Create a flatMap transducer.
     *
     * @example
     * xf := Xf.FlatMap((x) => [x, x * 2])
     * Xf.Into(xf, [1, 2, 3]) ; [1, 2, 2, 4, 3, 6]
     *
     * @param   {Func}  Fn  function returning iterable
     * @returns {Func}
     */
    static FlatMap(Fn) {
        return (Reducer) => (Acc, X) {
            for Item in Fn(X) {
                Acc := Reducer(Acc, Item)
                if (Acc is Reduced)
                    return Acc
            }
            return Acc
        }
    }

    /**
     * Create a flatten transducer.
     *
     * @returns {Func}
     */
    static Flatten() {
        return Xf.FlatMap((x) => x)
    }

    /**
     * Create a dedupe transducer that removes consecutive duplicates.
     *
     * @example
     * xf := Xf.Dedupe()
     * Xf.Into(xf, [1, 1, 2, 2, 2, 3, 1]) ; [1, 2, 3, 1]
     *
     * @returns {Func}
     */
    static Dedupe() {
        return (Reducer) {
            Prev := {}  ; Use object as sentinel for "no value"
            return (Acc, X) {
                if (Prev != {} && Prev = X)
                    return Acc
                Prev := X
                return Reducer(Acc, X)
            }
        }
    }

    /**
     * Create a distinct transducer that removes all duplicates.
     *
     * @example
     * xf := Xf.Distinct()
     * Xf.Into(xf, [1, 2, 1, 3, 2, 4]) ; [1, 2, 3, 4]
     *
     * @returns {Func}
     */
    static Distinct() {
        return (Reducer) {
            Seen := Map()
            return (Acc, X) {
                Key := IsObject(X) ? ObjPtr(X) : X
                if (Seen.Has(Key))
                    return Acc
                Seen[Key] := true
                return Reducer(Acc, X)
            }
        }
    }

    /**
     * Create a distinct-by transducer using a key function.
     *
     * @param   {Func}  KeyFn  function to extract comparison key
     * @returns {Func}
     */
    static DistinctBy(KeyFn) {
        return (Reducer) {
            Seen := Map()
            return (Acc, X) {
                Key := KeyFn(X)
                if (Seen.Has(Key))
                    return Acc
                Seen[Key] := true
                return Reducer(Acc, X)
            }
        }
    }

    /**
     * Create a partition transducer that groups elements.
     *
     * @example
     * xf := Xf.Partition(2)
     * Xf.Into(xf, [1,2,3,4,5]) ; [[1,2], [3,4], [5]]
     *
     * @param   {Integer}  N  partition size
     * @returns {Func}
     */
    static Partition(N) {
        return (Reducer) {
            Part := []
            return (Acc, X) {
                Part.Push(X)
                if (Part.Length = N) {
                    Result := Reducer(Acc, Part)
                    Part := []
                    return Result
                }
                return Acc
            }
        }
    }

    /**
     * Create a partition-by transducer.
     *
     * @param   {Func}  Fn  partitioning function
     * @returns {Func}
     */
    static PartitionBy(Fn) {
        return (Reducer) {
            Part := []
            LastKey := {}  ; Sentinel
            return (Acc, X) {
                Key := Fn(X)
                if (LastKey != {} && Key != LastKey && Part.Length > 0) {
                    Result := Reducer(Acc, Part)
                    Part := [X]
                    LastKey := Key
                    return Result
                }
                Part.Push(X)
                LastKey := Key
                return Acc
            }
        }
    }

    /**
     * Create an interpose transducer that inserts separator between elements.
     *
     * @example
     * xf := Xf.Interpose(0)
     * Xf.Into(xf, [1, 2, 3]) ; [1, 0, 2, 0, 3]
     *
     * @param   {Any}  Sep  separator value
     * @returns {Func}
     */
    static Interpose(Sep) {
        return (Reducer) {
            First := true
            return (Acc, X) {
                if (First) {
                    First := false
                    return Reducer(Acc, X)
                }
                Acc := Reducer(Acc, Sep)
                if (Acc is Reduced)
                    return Acc
                return Reducer(Acc, X)
            }
        }
    }

    /**
     * Create a mapIndexed transducer.
     *
     * @example
     * xf := Xf.MapIndexed((x, i) => x * i)
     * Xf.Into(xf, [10, 20, 30]) ; [10, 40, 90]
     *
     * @param   {Func}  Fn  function (value, index) => result
     * @returns {Func}
     */
    static MapIndexed(Fn) {
        return (Reducer) {
            Idx := 0
            return (Acc, X) => Reducer(Acc, Fn(X, ++Idx))
        }
    }

    /**
     * Create a scan transducer (running reduce).
     *
     * @example
     * xf := Xf.Scan((acc, x) => acc + x, 0)
     * Xf.Into(xf, [1, 2, 3, 4]) ; [1, 3, 6, 10]
     *
     * @param   {Func}  Fn    reducer function
     * @param   {Any}   Init  initial value
     * @returns {Func}
     */
    static Scan(Fn, Init) {
        return (Reducer) {
            Acc := Init
            return (Result, X) {
                Acc := Fn(Acc, X)
                return Reducer(Result, Acc)
            }
        }
    }

    /**
     * Create a keep transducer (map + filter for truthy).
     *
     * @param   {Func}  Fn  transformation function
     * @returns {Func}
     */
    static Keep(Fn) {
        return (Reducer) => (Acc, X) {
            V := Fn(X)
            return V ? Reducer(Acc, V) : Acc
        }
    }

    /**
     * Create a mapcat transducer (mapcat = flatMap in Clojure).
     * Alias for FlatMap.
     *
     * @param   {Func}  Fn
     * @returns {Func}
     */
    static MapCat(Fn) => Xf.FlatMap(Fn)

    ;---------------------------------------------------------------------------
    ; Composition and Execution
    ;---------------------------------------------------------------------------

    /**
     * Compose multiple transducers (right to left composition).
     *
     * @example
     * xform := Xf.Compose(
     *     Xf.Filter((x) => Mod(x, 2) = 0),
     *     Xf.Map((x) => x * 2),
     *     Xf.Take(5)
     * )
     *
     * @param   {Func*}  Xforms  transducers to compose
     * @returns {Func}
     */
    static Compose(Xforms*) {
        return (Reducer) {
            R := Reducer
            Loop Xforms.Length
                R := Xforms[Xforms.Length - A_Index + 1](R)
            return R
        }
    }

    /**
     * Compose multiple transducers (left to right composition).
     *
     * @param   {Func*}  Xforms  transducers to compose
     * @returns {Func}
     */
    static Pipe(Xforms*) {
        return (Reducer) {
            R := Reducer
            Loop Xforms.Length
                R := Xforms[A_Index](R)
            return R
        }
    }

    /**
     * Apply a transducer to reduce a collection.
     *
     * @param   {Func}   Xform    transducer
     * @param   {Func}   Reducer  reducer function
     * @param   {Any}    Init     initial value
     * @param   {Array}  Coll     collection to process
     * @returns {Any}
     */
    static Transduce(Xform, Reducer, Init, Coll) {
        XfReducer := Xform(Reducer)
        Acc := Init
        for Item in Coll {
            Acc := XfReducer(Acc, Item)
            if (Acc is Reduced)
                return Acc.value
        }
        return Acc
    }

    /**
     * Transform collection into an array using a transducer.
     *
     * @example
     * result := Xf.Into(Xf.Map((x) => x * 2), [1, 2, 3])
     * ; result = [2, 4, 6]
     *
     * @param   {Func}   Xform  transducer
     * @param   {Array}  Coll   collection to process
     * @returns {Array}
     */
    static Into(Xform, Coll) {
        return Xf.Transduce(
            Xform,
            (Acc, X) => (Acc.Push(X), Acc),
            [],
            Coll
        )
    }

    /**
     * Transform collection into a Map using a transducer.
     *
     * @param   {Func}   Xform  transducer producing [key, value] pairs
     * @param   {Array}  Coll   collection to process
     * @returns {Map}
     */
    static IntoMap(Xform, Coll) {
        return Xf.Transduce(
            Xform,
            (Acc, Pair) => (Acc[Pair[1]] := Pair[2], Acc),
            Map(),
            Coll
        )
    }

    /**
     * Transform collection into a string using a transducer.
     *
     * @param   {Func}    Xform  transducer
     * @param   {String}  Sep    separator
     * @param   {Array}   Coll   collection to process
     * @returns {String}
     */
    static IntoString(Xform, Sep, Coll) {
        return Xf.Transduce(
            Xform,
            (Acc, X) => Acc = "" ? String(X) : Acc . Sep . String(X),
            "",
            Coll
        )
    }

    /**
     * Apply transducer and return first result.
     *
     * @param   {Func}   Xform  transducer
     * @param   {Array}  Coll   collection
     * @returns {Optional}
     */
    static First(Xform, Coll) {
        Combined := Xf.Compose(Xform, Xf.Take(1))
        Result := Xf.Into(Combined, Coll)
        return Result.Length > 0 ? Optional(Result[1]) : Optional()
    }

    /**
     * Check if any element passes transducer and predicate.
     *
     * @param   {Func}   Xform  transducer
     * @param   {Func}   Pred   predicate
     * @param   {Array}  Coll   collection
     * @returns {Boolean}
     */
    static Some(Xform, Pred, Coll) {
        Combined := Xf.Compose(Xform, Xf.Filter(Pred), Xf.Take(1))
        return Xf.Into(Combined, Coll).Length > 0
    }

    /**
     * Check if all elements pass transducer and predicate.
     *
     * @param   {Func}   Xform  transducer
     * @param   {Func}   Pred   predicate
     * @param   {Array}  Coll   collection
     * @returns {Boolean}
     */
    static Every(Xform, Pred, Coll) {
        Combined := Xf.Compose(Xform, Xf.Remove(Pred), Xf.Take(1))
        return Xf.Into(Combined, Coll).Length = 0
    }

    /**
     * Count elements after applying transducer.
     *
     * @param   {Func}   Xform  transducer
     * @param   {Array}  Coll   collection
     * @returns {Integer}
     */
    static Count(Xform, Coll) {
        return Xf.Transduce(Xform, (Acc, *) => Acc + 1, 0, Coll)
    }

    /**
     * Fold/reduce after applying transducer.
     *
     * @param   {Func}   Xform    transducer
     * @param   {Func}   Reducer  fold function
     * @param   {Any}    Init     initial value
     * @param   {Array}  Coll     collection
     * @returns {Any}
     */
    static Fold(Xform, Reducer, Init, Coll) {
        return Xf.Transduce(Xform, Reducer, Init, Coll)
    }

    ;---------------------------------------------------------------------------
    ; Stateful Transducers
    ;---------------------------------------------------------------------------

    /**
     * Create a buffer transducer that collects N elements.
     *
     * @param   {Integer}  N  buffer size
     * @returns {Func}
     */
    static Buffer(N) {
        return (Reducer) {
            Buf := []
            return (Acc, X) {
                Buf.Push(X)
                if (Buf.Length = N) {
                    Result := Reducer(Acc, Buf)
                    Buf := []
                    return Result
                }
                return Acc
            }
        }
    }

    /**
     * Create a sliding window transducer.
     *
     * @example
     * xf := Xf.Window(3)
     * Xf.Into(xf, [1,2,3,4,5]) ; [[1,2,3], [2,3,4], [3,4,5]]
     *
     * @param   {Integer}  N  window size
     * @returns {Func}
     */
    static Window(N) {
        return (Reducer) {
            Win := []
            return (Acc, X) {
                Win.Push(X)
                if (Win.Length > N)
                    Win.RemoveAt(1)
                if (Win.Length = N)
                    return Reducer(Acc, Win.Clone())
                return Acc
            }
        }
    }

    /**
     * Create a random sample transducer.
     *
     * @param   {Float}  Prob  probability (0.0 to 1.0)
     * @returns {Func}
     */
    static Sample(Prob) {
        return (Reducer) => (Acc, X) {
            return Random() < Prob ? Reducer(Acc, X) : Acc
        }
    }

    /**
     * Identity transducer (passes through unchanged).
     *
     * @returns {Func}
     */
    static Identity() {
        return (Reducer) => Reducer
    }
}

;@region Reduced
/**
 * Reduced - Wrapper to signal early termination.
 *
 * When a transducer returns a Reduced value, processing stops immediately.
 */
class Reduced {
    /**
     * @param   {Any}  Value  the final value
     */
    __New(Value) {
        this.value := Value
    }

    /**
     * Check if a value is Reduced.
     *
     * @param   {Any}  X
     * @returns {Boolean}
     */
    static IsReduced(X) => X is Reduced

    /**
     * Unwrap a potentially Reduced value.
     *
     * @param   {Any}  X
     * @returns {Any}
     */
    static Unreduced(X) => X is Reduced ? X.value : X
}
;@endregion

;@region Extensions
class AquaHotkey_Transducer extends AquaHotkey {
    class Array {
        /**
         * Apply a transducer to this array.
         *
         * @example
         * [1,2,3,4,5].Transduce(Xf.Map((x) => x * 2)) ; [2,4,6,8,10]
         *
         * @param   {Func}  Xform  transducer
         * @returns {Array}
         */
        Transduce(Xform) => Xf.Into(Xform, this)

        /**
         * Apply a composed transducer pipeline to this array.
         *
         * @example
         * [1,2,3,4,5,6,7,8,9,10].XfPipe(
         *     Xf.Filter((x) => Mod(x, 2) = 0),
         *     Xf.Map((x) => x * 2),
         *     Xf.Take(3)
         * ) ; [4, 8, 12]
         *
         * @param   {Func*}  Xforms  transducers to apply
         * @returns {Array}
         */
        XfPipe(Xforms*) => Xf.Into(Xf.Compose(Xforms*), this)
    }

    class String {
        /**
         * Apply a transducer to this string's characters.
         *
         * @param   {Func}  Xform  transducer
         * @returns {Array}
         */
        TransduceChars(Xform) => Xf.Into(Xform, StrSplit(this))
    }
}
;@endregion
