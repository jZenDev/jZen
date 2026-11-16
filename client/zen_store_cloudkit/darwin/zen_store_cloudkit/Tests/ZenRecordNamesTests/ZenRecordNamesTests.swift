import CloudKit
import CryptoKit
import XCTest
@testable import ZenRecordNames

final class ZenRecordNamesTests: XCTestCase {
  private let names = ZenRecordNames(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
  private let zone = CKRecordZone.ID(zoneName: "zen_store_v2", ownerName: CKCurrentUserDefaultName)

  func testNoCollectionOrIdAppearsInARecordID() {
    let plain = ["budget:2026-11-EUR-groceries", "occurrence:plan42-2026-12-01"]
    for name in plain {
      let id = CKRecord.ID(recordName: names.hashed(name), zoneID: zone)
      for part in name.split(whereSeparator: { ":-".contains($0) }) {
        XCTAssertFalse(id.recordName.localizedCaseInsensitiveContains(part), "\(part) leaked into \(id.recordName)")
      }
      XCTAssertEqual(id.recordName.count, 64)
    }
  }

  func testNameIsStableAcrossDevicesAndDistinctPerName() {
    let other = ZenRecordNames(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
    XCTAssertEqual(names.hashed("a:1"), other.hashed("a:1"))
    XCTAssertNotEqual(names.hashed("a:1"), names.hashed("a:2"))
  }

  func testAnotherKeyGivesAnotherName() {
    let other = ZenRecordNames(key: SymmetricKey(data: Data(repeating: 8, count: 32)))
    XCTAssertNotEqual(names.hashed("a:1"), other.hashed("a:1"))
  }
}
