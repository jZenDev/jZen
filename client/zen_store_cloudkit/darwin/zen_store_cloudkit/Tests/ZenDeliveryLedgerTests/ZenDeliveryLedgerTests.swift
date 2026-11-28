import Foundation
import XCTest

@testable import ZenDeliveryLedger

final class ZenDeliveryLedgerTests: XCTestCase {
  func testAChangeDartTookLeavesTheStateToBeSaved() {
    var ledger = ZenDeliveryLedger()

    XCTAssertTrue(ledger.took(true))
    XCTAssertTrue(ledger.took(NSNumber(value: true)))

    XCTAssertTrue(ledger.maySaveState)
    XCTAssertTrue(ledger.mayReport("upToDate"))
  }

  func testAnyOtherReplyStopsTheStateBeingSaved() {
    // NSObject stands for FlutterError and FlutterMethodNotImplemented, which are objects.
    let replies: [Any?] = [nil, false, NSNull(), NSObject(), "true"]
    for reply in replies {
      var ledger = ZenDeliveryLedger()

      XCTAssertFalse(ledger.took(reply), "\(String(describing: reply))")

      XCTAssertFalse(ledger.maySaveState, "\(String(describing: reply))")
    }
  }

  func testALaterChangeDoesNotUndoALoss() {
    var ledger = ZenDeliveryLedger()
    ledger.lose()

    XCTAssertTrue(ledger.took(true))

    XCTAssertFalse(ledger.maySaveState)
  }

  func testAfterALossOnlyFailuresAreReported() {
    var ledger = ZenDeliveryLedger()
    ledger.lose()

    XCTAssertFalse(ledger.mayReport("syncing"))
    XCTAssertFalse(ledger.mayReport("upToDate"))
    XCTAssertTrue(ledger.mayReport("unavailable"))
  }
}
