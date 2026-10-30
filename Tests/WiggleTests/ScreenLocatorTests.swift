import CoreGraphics
import Testing
@testable import Wiggle

struct ScreenLocatorTests {
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: -200, width: 2560, height: 1440)

    @Test func findsTheDisplayUnderThePointer() {
        #expect(ScreenLocator.index(of: CGPoint(x: 700, y: 400), in: [builtIn, external]) == 0)
        #expect(ScreenLocator.index(of: CGPoint(x: 2000, y: 900), in: [builtIn, external]) == 1)
    }

    @Test func countsTheTopAndRightEdges() {
        // At the top row of a display the pointer's y equals maxY, which CGRect.contains rejects.
        #expect(ScreenLocator.index(of: CGPoint(x: 700, y: 982), in: [builtIn, external]) == 0)
        #expect(ScreenLocator.index(of: CGPoint(x: 4072, y: 1240), in: [builtIn, external]) == 1)
    }

    @Test func picksTheNearestDisplayWhenOffScreen() {
        #expect(ScreenLocator.index(of: CGPoint(x: -40, y: 400), in: [builtIn, external]) == 0)
        #expect(ScreenLocator.index(of: CGPoint(x: 3000, y: 1500), in: [builtIn, external]) == 1)
    }

    @Test func handlesNoDisplays() {
        #expect(ScreenLocator.index(of: .zero, in: []) == nil)
    }
}
