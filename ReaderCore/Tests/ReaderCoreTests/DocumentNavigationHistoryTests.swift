import Foundation
import Testing
@testable import ReaderCore

@Test func localHistoryRestoresLocationAndDropsForwardBranch() {
    let a = DocumentLocation(url: URL(fileURLWithPath: "/a.md"), scrollY: 440)
    let b = DocumentLocation(url: URL(fileURLWithPath: "/b.md"), scrollY: 220)
    var history = DocumentNavigationHistory()
    #expect(history.goBack(leaving: a) == nil)
    history.visit(leaving: a)
    #expect(history.goBack(leaving: b) == a)
    #expect(history.canGoForward)
    #expect(history.goForward(leaving: a) == b)
    #expect(history.goBack(leaving: b) == a)
    history.visit(leaving: a)
    #expect(!history.canGoForward)
}

@Test func localHistoryIsBoundedAndSanitizesScrollPositions() {
    var history = DocumentNavigationHistory()
    for index in 0..<200 {
        history.visit(leaving: DocumentLocation(url: URL(fileURLWithPath: "/\(index).md")))
    }
    var count = 0
    let current = DocumentLocation(url: URL(fileURLWithPath: "/current.md"), scrollY: .infinity)
    while history.goBack(leaving: current) != nil { count += 1 }
    #expect(count == 50)
    #expect(current.scrollY == 0)
}
