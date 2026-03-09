// Standalone test for SplitTree spatial navigation algorithm.
// Compile: swiftc -o /tmp/test_spatial Tests/test_spatial_navigation.swift Sources/Splits/SplitTree.swift -framework CoreGraphics -framework Foundation
// Run: /tmp/test_spatial

import CoreGraphics
import Foundation

// MARK: - Test infrastructure

class TestSurface: Identifiable {
    let id = UUID()
    let label: String
    init(_ label: String) { self.label = label }
}

var testsPassed = 0
var testsFailed = 0

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String, file: String = #file, line: Int = #line) {
    if a == b {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("FAIL [\(line)]: \(msg) — expected \(b), got \(a)")
    }
}

func assertNil<T>(_ a: T?, _ msg: String, file: String = #file, line: Int = #line) {
    if a == nil {
        testsPassed += 1
    } else {
        testsFailed += 1
        print("FAIL [\(line)]: \(msg) — expected nil, got \(a!)")
    }
}

// Helper to get label of a spatial navigation result
func navigate(
    tree: SplitTree<TestSurface>,
    from surface: TestSurface,
    direction: SplitTree<TestSurface>.Spatial.Direction
) -> String? {
    guard let root = tree.root,
          let node = root.find(id: surface.id),
          let result = tree.focusTarget(for: .spatial(direction), from: node) else {
        return nil
    }
    return result.label
}

// MARK: - Test cases

func testTwoPane_Horizontal() {
    print("\n--- Two panes horizontal: A | B ---")
    let a = TestSurface("A")
    let b = TestSurface("B")

    // A | B
    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.5,
                           left: .leaf(view: a), right: .leaf(view: b))),
        zoomed: nil
    )

    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right should be B")
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B → left should be A")
    assertNil(navigate(tree: tree, from: a, direction: .left), "A → left should be nil (boundary)")
    assertNil(navigate(tree: tree, from: b, direction: .right), "B → right should be nil (boundary)")
    assertNil(navigate(tree: tree, from: a, direction: .up), "A → up should be nil")
    assertNil(navigate(tree: tree, from: a, direction: .down), "A → down should be nil")
}

func testTwoPane_Vertical() {
    print("\n--- Two panes vertical: A over B ---")
    let a = TestSurface("A")
    let b = TestSurface("B")

    // A over B
    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .vertical, ratio: 0.5,
                           left: .leaf(view: a), right: .leaf(view: b))),
        zoomed: nil
    )

    assertEqual(navigate(tree: tree, from: a, direction: .down), "B", "A → down should be B")
    assertEqual(navigate(tree: tree, from: b, direction: .up), "A", "B → up should be A")
    assertNil(navigate(tree: tree, from: a, direction: .up), "A → up should be nil (boundary)")
    assertNil(navigate(tree: tree, from: b, direction: .down), "B → down should be nil (boundary)")
}

func test2x2Grid_VerticalFirst() {
    // Tree structure: vertical split first, then horizontal splits
    //   vertical(ratio=0.5)
    //   ├── horizontal(ratio=0.5) -> A(TL), B(TR)
    //   └── horizontal(ratio=0.5) -> C(BL), D(BR)
    //
    //  +---+---+
    //  | A | B |
    //  +---+---+
    //  | C | D |
    //  +---+---+

    print("\n--- 2x2 grid (vertical first): A B / C D ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .vertical, ratio: 0.5,
            left: .split(.init(direction: .horizontal, ratio: 0.5,
                               left: .leaf(view: a), right: .leaf(view: b))),
            right: .split(.init(direction: .horizontal, ratio: 0.5,
                                left: .leaf(view: c), right: .leaf(view: d))))),
        zoomed: nil
    )

    // From A (top-left)
    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B")
    assertEqual(navigate(tree: tree, from: a, direction: .down), "C", "A → down = C")
    assertNil(navigate(tree: tree, from: a, direction: .left), "A → left = nil")
    assertNil(navigate(tree: tree, from: a, direction: .up), "A → up = nil")

    // From B (top-right) — THE BUG: left should go to A, not C
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B(TR) → left = A(TL), NOT C(BL)")
    assertEqual(navigate(tree: tree, from: b, direction: .down), "D", "B → down = D")
    assertNil(navigate(tree: tree, from: b, direction: .right), "B → right = nil")
    assertNil(navigate(tree: tree, from: b, direction: .up), "B → up = nil")

    // From C (bottom-left)
    assertEqual(navigate(tree: tree, from: c, direction: .right), "D", "C → right = D")
    assertEqual(navigate(tree: tree, from: c, direction: .up), "A", "C → up = A")
    assertNil(navigate(tree: tree, from: c, direction: .left), "C → left = nil")
    assertNil(navigate(tree: tree, from: c, direction: .down), "C → down = nil")

    // From D (bottom-right)
    assertEqual(navigate(tree: tree, from: d, direction: .left), "C", "D(BR) → left = C(BL), NOT A(TL)")
    assertEqual(navigate(tree: tree, from: d, direction: .up), "B", "D → up = B")
    assertNil(navigate(tree: tree, from: d, direction: .right), "D → right = nil")
    assertNil(navigate(tree: tree, from: d, direction: .down), "D → down = nil")
}

func test2x2Grid_HorizontalFirst() {
    // Tree structure: horizontal split first, then vertical splits
    //   horizontal(ratio=0.5)
    //   ├── vertical(ratio=0.5) -> A(TL), C(BL)
    //   └── vertical(ratio=0.5) -> B(TR), D(BR)
    //
    //  +---+---+
    //  | A | B |
    //  +---+---+
    //  | C | D |
    //  +---+---+

    print("\n--- 2x2 grid (horizontal first): A B / C D ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.5,
            left: .split(.init(direction: .vertical, ratio: 0.5,
                               left: .leaf(view: a), right: .leaf(view: c))),
            right: .split(.init(direction: .vertical, ratio: 0.5,
                                left: .leaf(view: b), right: .leaf(view: d))))),
        zoomed: nil
    )

    // From A (top-left)
    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B")
    assertEqual(navigate(tree: tree, from: a, direction: .down), "C", "A → down = C")
    assertNil(navigate(tree: tree, from: a, direction: .left), "A → left = nil")
    assertNil(navigate(tree: tree, from: a, direction: .up), "A → up = nil")

    // From B (top-right) — THE BUG: left should go to A, not C
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B(TR) → left = A(TL), NOT C(BL)")
    assertEqual(navigate(tree: tree, from: b, direction: .down), "D", "B → down = D")
    assertNil(navigate(tree: tree, from: b, direction: .right), "B → right = nil")
    assertNil(navigate(tree: tree, from: b, direction: .up), "B → up = nil")

    // From C (bottom-left)
    assertEqual(navigate(tree: tree, from: c, direction: .right), "D", "C → right = D")
    assertEqual(navigate(tree: tree, from: c, direction: .up), "A", "C → up = A")
    assertNil(navigate(tree: tree, from: c, direction: .left), "C → left = nil")
    assertNil(navigate(tree: tree, from: c, direction: .down), "C → down = nil")

    // From D (bottom-right)
    assertEqual(navigate(tree: tree, from: d, direction: .left), "C", "D(BR) → left = C(BL), NOT A(TL)")
    assertEqual(navigate(tree: tree, from: d, direction: .up), "B", "D → up = B")
    assertNil(navigate(tree: tree, from: d, direction: .right), "D → right = nil")
    assertNil(navigate(tree: tree, from: d, direction: .down), "D → down = nil")
}

func test2x2Grid_CreatedByInsertion() {
    // Simulate actual user creation: split right from A, then split down from each half
    // 1. Start with A
    // 2. Split right from A → A | B (horizontal)
    // 3. Split down from A → (A / C) | B
    // 4. Split down from B → (A / C) | (B / D)

    print("\n--- 2x2 grid (created by insertion): A B / C D ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    var tree = SplitTree<TestSurface>(view: a)
    tree = try! tree.inserting(view: b, at: a, direction: .right)
    tree = try! tree.inserting(view: c, at: a, direction: .down)
    tree = try! tree.inserting(view: d, at: b, direction: .down)

    // Same expectations as the hand-built horizontal-first tree
    // From B (top-right) → left should be A (top-left)
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B(TR) → left = A(TL)")
    assertEqual(navigate(tree: tree, from: b, direction: .down), "D", "B → down = D")

    // From D (bottom-right) → left should be C (bottom-left)
    assertEqual(navigate(tree: tree, from: d, direction: .left), "C", "D(BR) → left = C(BL)")
    assertEqual(navigate(tree: tree, from: d, direction: .up), "B", "D → up = B")

    // From A (top-left)
    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B")
    assertEqual(navigate(tree: tree, from: a, direction: .down), "C", "A → down = C")

    // From C (bottom-left) → up should be A
    assertEqual(navigate(tree: tree, from: c, direction: .up), "A", "C → up = A")
    assertEqual(navigate(tree: tree, from: c, direction: .right), "D", "C → right = D")
}

func testAsymmetric_GhosttyStyle() {
    // Ghostty test case: asymmetric 2x2
    //   horizontal(ratio=0.5)
    //   ├── vertical(ratio=0.8) -> A(top, big), C(bottom, small)
    //   └── vertical(ratio=0.3) -> B(top, small), D(bottom, big)
    //
    //  +---++---+
    //  |   || B |
    //  |   |+---+
    //  |   |+---+
    //  | A ||   |
    //  |   ||   |
    //  |   || D |
    //  +---+|   |
    //  +---+|   |
    //  | C ||   |
    //  +---++---+

    print("\n--- Asymmetric (Ghostty test): A(tall) B(short) / C(short) D(tall) ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.5,
            left: .split(.init(direction: .vertical, ratio: 0.8,
                               left: .leaf(view: a), right: .leaf(view: c))),
            right: .split(.init(direction: .vertical, ratio: 0.3,
                                left: .leaf(view: b), right: .leaf(view: d))))),
        zoomed: nil
    )

    // Ghostty test: C → right = D
    assertEqual(navigate(tree: tree, from: c, direction: .right), "D", "C → right = D")

    // Ghostty test: D → left = A (A is closer than C to D's top-left)
    assertEqual(navigate(tree: tree, from: d, direction: .left), "A", "D → left = A (nearest)")

    // B → left = A
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B → left = A")

    // A → right = B (B is closer to A's top-left)
    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B")
}

func testThreePanes_Horizontal() {
    // A | B | C
    print("\n--- Three panes horizontal: A | B | C ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")

    // horizontal(A, horizontal(B, C))
    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.333,
            left: .leaf(view: a),
            right: .split(.init(direction: .horizontal, ratio: 0.5,
                                left: .leaf(view: b), right: .leaf(view: c))))),
        zoomed: nil
    )

    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B")
    assertEqual(navigate(tree: tree, from: b, direction: .right), "C", "B → right = C")
    assertEqual(navigate(tree: tree, from: c, direction: .left), "B", "C → left = B")
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B → left = A")
}

func testPreviousNext() {
    print("\n--- Previous/Next navigation ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")

    // horizontal(A, horizontal(B, C))
    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.333,
            left: .leaf(view: a),
            right: .split(.init(direction: .horizontal, ratio: 0.5,
                                left: .leaf(view: b), right: .leaf(view: c))))),
        zoomed: nil
    )

    func nav(_ surface: TestSurface, _ dir: SplitTree<TestSurface>.FocusDirection) -> String? {
        guard let root = tree.root,
              let node = root.find(id: surface.id),
              let result = tree.focusTarget(for: dir, from: node) else {
            return nil
        }
        return result.label
    }

    assertEqual(nav(a, .next), "B", "A → next = B")
    assertEqual(nav(b, .next), "C", "B → next = C")
    assertEqual(nav(c, .next), "A", "C → next = A (wraps)")
    assertEqual(nav(a, .previous), "C", "A → previous = C (wraps)")
    assertEqual(nav(c, .previous), "B", "C → previous = B")
}

func testLShape() {
    // L-shape: A is tall on the left, B and C stacked on the right
    //   horizontal(ratio=0.5)
    //   ├── A (full height)
    //   └── vertical(ratio=0.5) -> B(top), C(bottom)
    //
    //  +---+---+
    //  |   | B |
    //  | A +---+
    //  |   | C |
    //  +---+---+

    print("\n--- L-shape: A tall, B/C stacked ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")

    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.5,
            left: .leaf(view: a),
            right: .split(.init(direction: .vertical, ratio: 0.5,
                                left: .leaf(view: b), right: .leaf(view: c))))),
        zoomed: nil
    )

    // B → left = A
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "B → left = A")
    // C → left = A
    assertEqual(navigate(tree: tree, from: c, direction: .left), "A", "C → left = A")
    // A → right = B (B's top-left is closer to A's top-left)
    assertEqual(navigate(tree: tree, from: a, direction: .right), "B", "A → right = B (nearest)")
    // B → down = C
    assertEqual(navigate(tree: tree, from: b, direction: .down), "C", "B → down = C")
    // C → up = B
    assertEqual(navigate(tree: tree, from: c, direction: .up), "B", "C → up = B")
}

func testNoSplits() {
    print("\n--- Single pane (no splits) ---")
    let a = TestSurface("A")
    let tree = SplitTree<TestSurface>(view: a)

    assertNil(navigate(tree: tree, from: a, direction: .left), "A → left = nil (single pane)")
    assertNil(navigate(tree: tree, from: a, direction: .right), "A → right = nil (single pane)")
    assertNil(navigate(tree: tree, from: a, direction: .up), "A → up = nil (single pane)")
    assertNil(navigate(tree: tree, from: a, direction: .down), "A → down = nil (single pane)")
}

func test2x2Grid_Equalized() {
    // Test after equalization: tree structure might differ
    print("\n--- 2x2 grid equalized ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    // Create asymmetric tree and equalize
    var tree = SplitTree<TestSurface>(view: a)
    tree = try! tree.inserting(view: b, at: a, direction: .right)
    tree = try! tree.inserting(view: c, at: a, direction: .down)
    tree = try! tree.inserting(view: d, at: b, direction: .down)
    tree = tree.equalized()

    // B (top-right) → left = A (top-left)
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "Equalized: B(TR) → left = A(TL)")
    // D (bottom-right) → left = C (bottom-left)
    assertEqual(navigate(tree: tree, from: d, direction: .left), "C", "Equalized: D(BR) → left = C(BL)")
    // D → up = B
    assertEqual(navigate(tree: tree, from: d, direction: .up), "B", "Equalized: D → up = B")
    // C → up = A
    assertEqual(navigate(tree: tree, from: c, direction: .up), "A", "Equalized: C → up = A")
}

func test2x2Grid_UnequalRatios() {
    // What if ratios aren't 50/50?
    print("\n--- 2x2 grid with unequal ratios ---")
    let a = TestSurface("A")
    let b = TestSurface("B")
    let c = TestSurface("C")
    let d = TestSurface("D")

    // horizontal(ratio=0.3) ← A takes 30% width
    //   vertical(ratio=0.7) ← A takes 70% height
    //   vertical(ratio=0.3) ← B takes 30% height
    let tree = SplitTree<TestSurface>(
        root: .split(.init(direction: .horizontal, ratio: 0.3,
            left: .split(.init(direction: .vertical, ratio: 0.7,
                               left: .leaf(view: a), right: .leaf(view: c))),
            right: .split(.init(direction: .vertical, ratio: 0.3,
                                left: .leaf(view: b), right: .leaf(view: d))))),
        zoomed: nil
    )

    // B (top-right) → left = A (top-left)
    assertEqual(navigate(tree: tree, from: b, direction: .left), "A", "Unequal: B(TR) → left = A(TL)")
    // D → left = C or A? D is bottom-right, should go to C (bottom-left)
    // D's top-left: (0.3, 0.3). C's top-left: (0, 0.7). A's top-left: (0, 0)
    // dist(D→C) = sqrt(0.3² + (0.3-0.7)²) = sqrt(0.09 + 0.16) = sqrt(0.25) = 0.5
    // dist(D→A) = sqrt(0.3² + 0.3²) = sqrt(0.18) = 0.424
    // A is actually closer! This matches Ghostty behavior
    assertEqual(navigate(tree: tree, from: d, direction: .left), "A", "Unequal: D(BR) → left = A (nearest)")
}

// MARK: - Run all tests

@main struct TestRunner {
    static func main() {
        testNoSplits()
        testTwoPane_Horizontal()
        testTwoPane_Vertical()
        test2x2Grid_VerticalFirst()
        test2x2Grid_HorizontalFirst()
        test2x2Grid_CreatedByInsertion()
        testAsymmetric_GhosttyStyle()
        testThreePanes_Horizontal()
        testPreviousNext()
        testLShape()
        test2x2Grid_Equalized()
        test2x2Grid_UnequalRatios()

        print("\n=== Results: \(testsPassed) passed, \(testsFailed) failed ===")
        if testsFailed > 0 {
            exit(1)
        }
    }
}
