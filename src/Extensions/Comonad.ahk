#Requires AutoHotkey v2.1-alpha.16

;@region Comonad
/**
 * AquaHotkey - Comonad.ahk
 *
 * Author: 0w0Demonic
 *
 * https://www.github.com/0w0Demonic/AquaHotkey
 * - src/Extensions/Comonad.ahk
 *
 * ---
 *
 * **Overview**:
 *
 * Comonads are the categorical dual of monads. While monads are about putting
 * values into contexts (flatMap/bind), comonads are about extracting values
 * from contexts and extending computations to all possible contexts.
 *
 * Key operations:
 * - Extract: Get the value at the current focus
 * - Extend: Apply a function to all possible focuses
 * - Duplicate: Create a comonad of comonads
 *
 * Comonads are perfect for:
 * - Context-dependent computations (Store)
 * - Navigable data structures (Zipper)
 * - Cellular automata
 * - Image processing
 * - Local computations with neighborhood access
 *
 * @example
 * ; Moving average using ListZipper comonad
 * zipper := ListZipper.Of([1, 2, 3, 4, 5])
 * averages := zipper.Extend((z) {
 *     sum := z.Focus
 *     count := 1
 *     z.PeekLeft().IfPresent((v) => (sum += v, count++))
 *     z.PeekRight().IfPresent((v) => (sum += v, count++))
 *     return sum / count
 * }).ToArray()
 */

;---------------------------------------------------------------------------
;@region Store
/**
 * Store Comonad - Computation with a focus position.
 *
 * Store consists of a function that can look up any position and a
 * current position. It's like having a "cursor" into an infinite space.
 *
 * @example
 * ; A store representing a 1D array with position
 * store := Store((i) => data[i], currentIndex)
 * store.Extract()  ; Get value at current position
 * store.Seek(5)    ; Move to position 5
 * store.Peek(3)    ; Look at position 3 without moving
 */
class Store {
    /**
     * Constructs a Store comonad.
     *
     * @param   {Func}  Peek  function to look up any position
     * @param   {Any}   Pos   current position
     */
    __New(Peek, Pos) {
        this._peek := Peek
        this._pos := Pos
    }

    /**
     * Extract the value at the current position.
     * This is the comonadic 'extract' operation.
     *
     * @returns {Any}
     */
    Extract() => this._peek(this._pos)

    /**
     * Get the current position.
     *
     * @returns {Any}
     */
    Pos => this._pos

    /**
     * Look at a specific position without moving.
     *
     * @param   {Any}  P  position to peek
     * @returns {Any}
     */
    Peek(P) => this._peek(P)

    /**
     * Look at a position relative to current.
     *
     * @param   {Number}  Offset
     * @returns {Any}
     */
    PeekRel(Offset) => this._peek(this._pos + Offset)

    /**
     * Move to a new position.
     *
     * @param   {Any}  NewPos
     * @returns {Store}
     */
    Seek(NewPos) => Store(this._peek, NewPos)

    /**
     * Move relative to current position.
     *
     * @param   {Number}  Offset
     * @returns {Store}
     */
    SeekRel(Offset) => Store(this._peek, this._pos + Offset)

    /**
     * Extend a computation to all positions.
     * The function receives a Store focused at each position.
     *
     * @example
     * ; Blur effect: average of neighbors
     * blurred := image.Extend((s) {
     *     return (s.Peek(s.Pos - 1) + s.Extract() + s.Peek(s.Pos + 1)) / 3
     * })
     *
     * @param   {Func}  Fn  (Store) => value
     * @returns {Store}
     */
    Extend(Fn) {
        return Store((P) => Fn(Store(this._peek, P)), this._pos)
    }

    /**
     * Duplicate: create a Store of Stores.
     *
     * @returns {Store}
     */
    Duplicate() => this.Extend((s) => s)

    /**
     * Map over the values (post-composition).
     *
     * @param   {Func}  Fn
     * @returns {Store}
     */
    Map(Fn) => Store((P) => Fn(this._peek(P)), this._pos)

    /**
     * Get all values in a range.
     *
     * @param   {Array}  Positions  array of positions
     * @returns {Array}
     */
    Experiment(Positions) {
        Result := []
        for P in Positions
            Result.Push(this._peek(P))
        return Result
    }

    /**
     * Get values in a numeric range.
     *
     * @param   {Integer}  Start
     * @param   {Integer}  End
     * @returns {Array}
     */
    Range(Start, End) {
        Result := []
        Loop End - Start + 1
            Result.Push(this._peek(Start + A_Index - 1))
        return Result
    }

    /**
     * Create a Store from an array.
     *
     * @param   {Array}    Arr
     * @param   {Integer}  Pos
     * @returns {Store}
     */
    static FromArray(Arr, Pos := 1) {
        return Store((I) => (I >= 1 && I <= Arr.Length) ? Arr[I] : "", Pos)
    }

    /**
     * Create a 2D Store (for images, grids, etc.).
     *
     * @param   {Func}   Peek   (x, y) => value
     * @param   {Array}  Pos    [x, y]
     * @returns {Store2D}
     */
    static Grid(Peek, Pos) => Store2D(Peek, Pos)
}
;@endregion

;---------------------------------------------------------------------------
;@region Store2D
/**
 * Store2D - 2D Store comonad for grids/images.
 *
 * @example
 * ; Conway's Game of Life
 * grid := Store2D((x, y) => cells[x][y], [5, 5])
 * nextGen := grid.Extend((s) {
 *     neighbors := s.CountNeighbors()
 *     alive := s.Extract()
 *     return (alive && neighbors = 2 or 3) || (!alive && neighbors = 3)
 * })
 */
class Store2D {
    __New(Peek, Pos) {
        this._peek := Peek
        this._pos := Pos
    }

    Extract() => this._peek(this._pos[1], this._pos[2])

    X => this._pos[1]
    Y => this._pos[2]
    Pos => this._pos

    Peek(X, Y) => this._peek(X, Y)
    PeekAt(Pos) => this._peek(Pos[1], Pos[2])

    Seek(X, Y) => Store2D(this._peek, [X, Y])
    SeekRel(DX, DY) => Store2D(this._peek, [this._pos[1] + DX, this._pos[2] + DY])

    Extend(Fn) {
        return Store2D((X, Y) => Fn(Store2D(this._peek, [X, Y])), this._pos)
    }

    Duplicate() => this.Extend((s) => s)

    Map(Fn) => Store2D((X, Y) => Fn(this._peek(X, Y)), this._pos)

    /**
     * Get all 8 neighbors (Moore neighborhood).
     *
     * @returns {Array}
     */
    Neighbors() {
        X := this._pos[1]
        Y := this._pos[2]
        return [
            this._peek(X-1, Y-1), this._peek(X, Y-1), this._peek(X+1, Y-1),
            this._peek(X-1, Y),                       this._peek(X+1, Y),
            this._peek(X-1, Y+1), this._peek(X, Y+1), this._peek(X+1, Y+1)
        ]
    }

    /**
     * Get 4 cardinal neighbors (Von Neumann neighborhood).
     *
     * @returns {Array}
     */
    CardinalNeighbors() {
        X := this._pos[1]
        Y := this._pos[2]
        return [
            this._peek(X, Y-1),
            this._peek(X-1, Y), this._peek(X+1, Y),
            this._peek(X, Y+1)
        ]
    }

    /**
     * Count truthy neighbors.
     *
     * @returns {Integer}
     */
    CountNeighbors() {
        Count := 0
        for N in this.Neighbors()
            if (N)
                Count++
        return Count
    }

    /**
     * Apply convolution kernel.
     *
     * @param   {Array}  Kernel  3x3 kernel
     * @returns {Number}
     */
    Convolve(Kernel) {
        X := this._pos[1]
        Y := this._pos[2]
        Sum := 0
        for I, Row in Kernel {
            for J, W in Row {
                Sum += W * this._peek(X + J - 2, Y + I - 2)
            }
        }
        return Sum
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region ListZipper
/**
 * ListZipper Comonad - Navigable list with focus.
 *
 * A zipper is a data structure that represents a list with a "focus"
 * that can be efficiently moved left or right.
 *
 * @example
 * zipper := ListZipper.Of([1, 2, 3, 4, 5], 3)  ; Focus on 3
 * zipper.Extract()     ; 3
 * zipper.MoveLeft()    ; Focus on 2
 * zipper.MoveRight()   ; Focus on 4
 */
class ListZipper {
    /**
     * Constructs a ListZipper.
     *
     * @param   {Array}  Left   elements to the left (reversed order)
     * @param   {Any}    Focus  focused element
     * @param   {Array}  Right  elements to the right
     */
    __New(Left, Focus, Right) {
        this._left := Left
        this._focus := Focus
        this._right := Right
    }

    /**
     * Create a ListZipper from an array.
     *
     * @param   {Array}    Arr  source array
     * @param   {Integer}  Pos  1-based position to focus (default: 1)
     * @returns {ListZipper}
     */
    static Of(Arr, Pos := 1) {
        if (Arr.Length = 0)
            throw ValueError("Cannot create zipper from empty array")

        if (Pos < 1 || Pos > Arr.Length)
            throw ValueError("Position out of bounds")

        Left := []
        Loop Pos - 1
            Left.InsertAt(1, Arr[A_Index])

        Focus := Arr[Pos]

        Right := []
        Loop Arr.Length - Pos
            Right.Push(Arr[Pos + A_Index])

        return ListZipper(Left, Focus, Right)
    }

    /**
     * Extract the focused element.
     *
     * @returns {Any}
     */
    Extract() => this._focus

    /**
     * Alias for Extract.
     */
    Focus => this._focus

    /**
     * Get left elements (in original order).
     */
    Left => this._left.Clone()

    /**
     * Get right elements.
     */
    Right => this._right.Clone()

    /**
     * Get the length of the underlying list.
     */
    Length => this._left.Length + 1 + this._right.Length

    /**
     * Get current position (1-based).
     */
    Position => this._left.Length + 1

    /**
     * Move focus one position left.
     * Returns Optional.Empty() if at start.
     *
     * @returns {Optional}
     */
    MoveLeft() {
        if (this._left.Length = 0)
            return Optional()

        NewLeft := this._left.Clone()
        NewFocus := NewLeft.Pop()
        NewRight := [this._focus, this._right*]
        return Optional(ListZipper(NewLeft, NewFocus, NewRight))
    }

    /**
     * Move focus one position right.
     * Returns Optional.Empty() if at end.
     *
     * @returns {Optional}
     */
    MoveRight() {
        if (this._right.Length = 0)
            return Optional()

        NewRight := this._right.Clone()
        NewFocus := NewRight.RemoveAt(1)
        NewLeft := [this._left*, this._focus]
        return Optional(ListZipper(NewLeft, NewFocus, NewRight))
    }

    /**
     * Move to start of list.
     *
     * @returns {ListZipper}
     */
    MoveToStart() {
        Current := this
        while (Current._left.Length > 0)
            Current := Current.MoveLeft().Value
        return Current
    }

    /**
     * Move to end of list.
     *
     * @returns {ListZipper}
     */
    MoveToEnd() {
        Current := this
        while (Current._right.Length > 0)
            Current := Current.MoveRight().Value
        return Current
    }

    /**
     * Move to specific position.
     *
     * @param   {Integer}  Pos  1-based position
     * @returns {Optional}
     */
    MoveTo(Pos) {
        if (Pos < 1 || Pos > this.Length)
            return Optional()

        Current := this.MoveToStart()
        Loop Pos - 1
            Current := Current.MoveRight().Value
        return Optional(Current)
    }

    /**
     * Peek at element to the left.
     *
     * @returns {Optional}
     */
    PeekLeft() {
        return this._left.Length > 0
            ? Optional(this._left[this._left.Length])
            : Optional()
    }

    /**
     * Peek at element to the right.
     *
     * @returns {Optional}
     */
    PeekRight() {
        return this._right.Length > 0
            ? Optional(this._right[1])
            : Optional()
    }

    /**
     * Update the focused element.
     *
     * @param   {Any}  NewValue
     * @returns {ListZipper}
     */
    Set(NewValue) => ListZipper(this._left, NewValue, this._right)

    /**
     * Modify the focused element.
     *
     * @param   {Func}  Fn
     * @returns {ListZipper}
     */
    Modify(Fn) => ListZipper(this._left, Fn(this._focus), this._right)

    /**
     * Insert element to the left of focus.
     *
     * @param   {Any}  Value
     * @returns {ListZipper}
     */
    InsertLeft(Value) {
        NewLeft := [this._left*, Value]
        return ListZipper(NewLeft, this._focus, this._right)
    }

    /**
     * Insert element to the right of focus.
     *
     * @param   {Any}  Value
     * @returns {ListZipper}
     */
    InsertRight(Value) {
        NewRight := [Value, this._right*]
        return ListZipper(this._left, this._focus, NewRight)
    }

    /**
     * Delete the focused element.
     * Focus moves right if possible, otherwise left.
     *
     * @returns {Optional}
     */
    Delete() {
        if (this._right.Length > 0) {
            NewRight := this._right.Clone()
            NewFocus := NewRight.RemoveAt(1)
            return Optional(ListZipper(this._left, NewFocus, NewRight))
        }
        if (this._left.Length > 0) {
            NewLeft := this._left.Clone()
            NewFocus := NewLeft.Pop()
            return Optional(ListZipper(NewLeft, NewFocus, this._right))
        }
        return Optional()
    }

    /**
     * Extend a computation to all positions.
     *
     * @param   {Func}  Fn  (ListZipper) => value
     * @returns {ListZipper}
     */
    Extend(Fn) {
        ; Compute values for all left positions
        Lefts := []
        Current := this
        while (Current._left.Length > 0) {
            Current := Current.MoveLeft().Value
            Lefts.InsertAt(1, Fn(Current))
        }

        ; Compute values for all right positions
        Rights := []
        Current := this
        while (Current._right.Length > 0) {
            Current := Current.MoveRight().Value
            Rights.Push(Fn(Current))
        }

        return ListZipper(Lefts, Fn(this), Rights)
    }

    /**
     * Duplicate: create a zipper of zippers.
     *
     * @returns {ListZipper}
     */
    Duplicate() => this.Extend((z) => z)

    /**
     * Map over all elements.
     *
     * @param   {Func}  Fn
     * @returns {ListZipper}
     */
    Map(Fn) {
        NewLeft := []
        for V in this._left
            NewLeft.Push(Fn(V))
        NewRight := []
        for V in this._right
            NewRight.Push(Fn(V))
        return ListZipper(NewLeft, Fn(this._focus), NewRight)
    }

    /**
     * Convert back to array.
     *
     * @returns {Array}
     */
    ToArray() {
        Result := []
        Loop this._left.Length
            Result.Push(this._left[this._left.Length - A_Index + 1])
        Result.Push(this._focus)
        for V in this._right
            Result.Push(V)
        return Result
    }

    /**
     * Get window of elements around focus.
     *
     * @param   {Integer}  Size  elements on each side
     * @returns {Array}
     */
    Window(Size) {
        Result := []
        Loop Size {
            Idx := this._left.Length - Size + A_Index
            if (Idx >= 1 && Idx <= this._left.Length)
                Result.Push(this._left[Idx])
        }
        Result.Push(this._focus)
        Loop Size {
            if (A_Index <= this._right.Length)
                Result.Push(this._right[A_Index])
        }
        return Result
    }

    ToString() {
        L := this._left.Length > 0 ? "[" . this._left.Join(", ") . "]" : "[]"
        R := this._right.Length > 0 ? "[" . this._right.Join(", ") . "]" : "[]"
        return "ListZipper(" . L . " <" . this._focus . "> " . R . ")"
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region TreeZipper
/**
 * TreeZipper - Navigable tree with focus.
 *
 * Allows efficient navigation and modification of tree structures.
 *
 * @example
 * tree := TreeNode("root", [
 *     TreeNode("child1"),
 *     TreeNode("child2", [TreeNode("grandchild")])
 * ])
 * zipper := TreeZipper.Of(tree)
 * zipper.Down()      ; Focus on first child
 * zipper.Right()     ; Focus on sibling
 * zipper.Up()        ; Back to parent
 */
class TreeZipper {
    __New(Focus, Context) {
        this._focus := Focus
        this._context := Context
    }

    /**
     * Create a TreeZipper from a tree root.
     *
     * @param   {TreeNode}  Root
     * @returns {TreeZipper}
     */
    static Of(Root) => TreeZipper(Root, [])

    /**
     * Extract the focused node.
     *
     * @returns {TreeNode}
     */
    Extract() => this._focus

    /**
     * Get focused node's value.
     */
    Value => this._focus.value

    /**
     * Check if at root.
     */
    IsRoot => this._context.Length = 0

    /**
     * Move to first child.
     *
     * @returns {Optional}
     */
    Down() {
        if (!this._focus.HasChildren())
            return Optional()

        Children := this._focus.children
        FirstChild := Children[1]
        Siblings := []
        Loop Children.Length - 1
            Siblings.Push(Children[A_Index + 1])

        NewContext := [{
            parent: this._focus,
            left: [],
            right: Siblings
        }, this._context*]

        return Optional(TreeZipper(FirstChild, NewContext))
    }

    /**
     * Move to parent.
     *
     * @returns {Optional}
     */
    Up() {
        if (this._context.Length = 0)
            return Optional()

        Ctx := this._context[1]
        RestContext := []
        Loop this._context.Length - 1
            RestContext.Push(this._context[A_Index + 1])

        ; Reconstruct parent with modified children
        NewChildren := []
        Loop Ctx.left.Length
            NewChildren.Push(Ctx.left[Ctx.left.Length - A_Index + 1])
        NewChildren.Push(this._focus)
        for R in Ctx.right
            NewChildren.Push(R)

        NewFocus := TreeNode(Ctx.parent.value, NewChildren)
        return Optional(TreeZipper(NewFocus, RestContext))
    }

    /**
     * Move to right sibling.
     *
     * @returns {Optional}
     */
    Right() {
        if (this._context.Length = 0)
            return Optional()

        Ctx := this._context[1]
        if (Ctx.right.Length = 0)
            return Optional()

        NewRight := Ctx.right.Clone()
        NewFocus := NewRight.RemoveAt(1)
        NewLeft := [Ctx.left*, this._focus]

        NewContext := [{
            parent: Ctx.parent,
            left: NewLeft,
            right: NewRight
        }]
        Loop this._context.Length - 1
            NewContext.Push(this._context[A_Index + 1])

        return Optional(TreeZipper(NewFocus, NewContext))
    }

    /**
     * Move to left sibling.
     *
     * @returns {Optional}
     */
    Left() {
        if (this._context.Length = 0)
            return Optional()

        Ctx := this._context[1]
        if (Ctx.left.Length = 0)
            return Optional()

        NewLeft := Ctx.left.Clone()
        NewFocus := NewLeft.Pop()
        NewRight := [this._focus, Ctx.right*]

        NewContext := [{
            parent: Ctx.parent,
            left: NewLeft,
            right: NewRight
        }]
        Loop this._context.Length - 1
            NewContext.Push(this._context[A_Index + 1])

        return Optional(TreeZipper(NewFocus, NewContext))
    }

    /**
     * Move to root.
     *
     * @returns {TreeZipper}
     */
    Root() {
        Current := this
        while (Current._context.Length > 0)
            Current := Current.Up().Value
        return Current
    }

    /**
     * Modify focused node's value.
     *
     * @param   {Func}  Fn
     * @returns {TreeZipper}
     */
    Modify(Fn) {
        NewFocus := TreeNode(Fn(this._focus.value), this._focus.children)
        return TreeZipper(NewFocus, this._context)
    }

    /**
     * Replace focused node.
     *
     * @param   {TreeNode}  NewNode
     * @returns {TreeZipper}
     */
    Replace(NewNode) => TreeZipper(NewNode, this._context)

    /**
     * Insert child at beginning.
     *
     * @param   {TreeNode}  Child
     * @returns {TreeZipper}
     */
    InsertChild(Child) {
        NewChildren := [Child, this._focus.children*]
        NewFocus := TreeNode(this._focus.value, NewChildren)
        return TreeZipper(NewFocus, this._context)
    }

    /**
     * Delete focused node (moves to right sibling, then left, then parent).
     *
     * @returns {Optional}
     */
    Delete() {
        if (this._context.Length = 0)
            return Optional()

        Ctx := this._context[1]

        if (Ctx.right.Length > 0)
            return this.Right().Map((z) => TreeZipper(z._focus, [{
                parent: Ctx.parent,
                left: Ctx.left,
                right: z._context[1].right
            }, this._context.Slice(2)*]))

        if (Ctx.left.Length > 0)
            return this.Left()

        return this.Up()
    }

    /**
     * Get the reconstructed tree.
     *
     * @returns {TreeNode}
     */
    ToTree() => this.Root()._focus
}

/**
 * TreeNode - Simple tree node structure for TreeZipper.
 */
class TreeNode {
    __New(Value, Children := []) {
        this.value := Value
        this.children := Children
    }

    HasChildren() => this.children.Length > 0

    Map(Fn) {
        NewChildren := []
        for C in this.children
            NewChildren.Push(C.Map(Fn))
        return TreeNode(Fn(this.value), NewChildren)
    }

    FoldL(Fn, Init) {
        Acc := Fn(Init, this.value)
        for C in this.children
            Acc := C.FoldL(Fn, Acc)
        return Acc
    }
}
;@endregion

;---------------------------------------------------------------------------
;@region Traced
/**
 * Traced Comonad - Computation with a monoidal trace.
 *
 * Dual of Writer monad. Instead of accumulating output, it consumes input.
 *
 * @example
 * ; Configuration reader with additive offsets
 * config := Traced((offset) => baseValue + offset)
 */
class Traced {
    __New(Run) {
        this._run := Run
    }

    /**
     * Extract value at the "empty" trace (0 for numbers, "" for strings).
     */
    Extract() => this._run(0)

    /**
     * Run with a specific trace.
     */
    RunTraced(Trace) => this._run(Trace)

    /**
     * Extend computation.
     */
    Extend(Fn) {
        return Traced((T1) => Fn(Traced((T2) => this._run(T1 + T2))))
    }

    Duplicate() => this.Extend((t) => t)

    Map(Fn) => Traced((T) => Fn(this._run(T)))

    static Of(Value) => Traced((*) => Value)
}
;@endregion

;---------------------------------------------------------------------------
;@region Extensions
class AquaHotkey_Comonad extends AquaHotkey {
    class Array {
        /**
         * Create a ListZipper from this array.
         *
         * @param   {Integer}  Pos  focus position (default: 1)
         * @returns {ListZipper}
         */
        ToZipper(Pos := 1) => ListZipper.Of(this, Pos)

        /**
         * Create a Store comonad backed by this array.
         *
         * @param   {Integer}  Pos  initial position
         * @returns {Store}
         */
        ToStore(Pos := 1) => Store.FromArray(this, Pos)

        /**
         * Join array elements.
         *
         * @param   {String}  Sep
         * @returns {String}
         */
        Join(Sep := ", ") {
            if (this.Length = 0)
                return ""
            Result := String(this[1])
            Loop this.Length - 1
                Result .= Sep . String(this[A_Index + 1])
            return Result
        }

        /**
         * Slice array from start to end.
         *
         * @param   {Integer}  Start
         * @param   {Integer}  End
         * @returns {Array}
         */
        Slice(Start := 1, End?) {
            if (!IsSet(End))
                End := this.Length
            Result := []
            Loop End - Start + 1
                Result.Push(this[Start + A_Index - 1])
            return Result
        }
    }
}
;@endregion
