import XCTest
import CoreGraphics

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class WorkspaceContentViewVisibilityTests: XCTestCase {
    func testPanelVisibleInUIReturnsFalseWhenWorkspaceHidden() {
        XCTAssertFalse(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: false,
                isSelectedInPane: true,
                isFocused: true
            )
        )
    }

    func testPanelVisibleInUIReturnsTrueForSelectedPanel() {
        XCTAssertTrue(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: true,
                isFocused: false
            )
        )
    }

    func testPanelVisibleInUIReturnsTrueForFocusedPanelDuringTransientSelectionGap() {
        XCTAssertTrue(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: false,
                isFocused: true
            )
        )
    }

    func testPanelVisibleInUIReturnsFalseWhenNeitherSelectedNorFocused() {
        XCTAssertFalse(
            WorkspaceContentView.panelVisibleInUI(
                isWorkspaceVisible: true,
                isSelectedInPane: false,
                isFocused: false
            )
        )
    }

    func testPortalHostLeasingStateRejectsSmallerSameContextReplacementByDefault() {
        var leasing = PortalHostLeasingState()
        let contextId = UUID()
        let firstHost = NSObject()
        let secondHost = NSObject()

        let firstClaim = leasing.claim(
            hostId: ObjectIdentifier(firstHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        XCTAssertTrue(firstClaim.accepted)

        let secondClaim = leasing.claim(
            hostId: ObjectIdentifier(secondHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 80, height: 80)
        )

        XCTAssertFalse(secondClaim.accepted)
        XCTAssertEqual(secondClaim.activeLease?.hostId, ObjectIdentifier(firstHost))
        XCTAssertFalse(secondClaim.blockedByLock)
    }

    func testPortalHostLeasingStateForcesDistinctReplacementWhenArmed() {
        var leasing = PortalHostLeasingState()
        let contextId = UUID()
        let firstHost = NSObject()
        let secondHost = NSObject()

        _ = leasing.claim(
            hostId: ObjectIdentifier(firstHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        leasing.prepareForNextDistinctReplacement(contextId: contextId)

        let forcedClaim = leasing.claim(
            hostId: ObjectIdentifier(secondHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 20)
        )

        XCTAssertTrue(forcedClaim.accepted)
        XCTAssertTrue(forcedClaim.forcedDistinctReplacement)
        XCTAssertEqual(forcedClaim.activeLease?.hostId, ObjectIdentifier(secondHost))
        XCTAssertEqual(forcedClaim.replacedLease?.hostId, ObjectIdentifier(firstHost))
    }

    func testPortalHostLeasingStateLocksForcedReplacementAgainstImmediateThrash() {
        var leasing = PortalHostLeasingState()
        let contextId = UUID()
        let firstHost = NSObject()
        let secondHost = NSObject()
        let thirdHost = NSObject()

        _ = leasing.claim(
            hostId: ObjectIdentifier(firstHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        leasing.prepareForNextDistinctReplacement(contextId: contextId)
        _ = leasing.claim(
            hostId: ObjectIdentifier(secondHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 20, height: 20)
        )

        let blockedClaim = leasing.claim(
            hostId: ObjectIdentifier(thirdHost),
            contextId: contextId,
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 400, height: 400)
        )

        XCTAssertFalse(blockedClaim.accepted)
        XCTAssertTrue(blockedClaim.blockedByLock)
        XCTAssertEqual(blockedClaim.activeLease?.hostId, ObjectIdentifier(secondHost))
    }

    func testPortalHostLeasingStateAllowsReplacementAcrossContexts() {
        var leasing = PortalHostLeasingState()
        let firstHost = NSObject()
        let secondHost = NSObject()

        _ = leasing.claim(
            hostId: ObjectIdentifier(firstHost),
            contextId: UUID(),
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )

        let secondClaim = leasing.claim(
            hostId: ObjectIdentifier(secondHost),
            contextId: UUID(),
            inWindow: true,
            bounds: CGRect(x: 0, y: 0, width: 40, height: 40)
        )

        XCTAssertTrue(secondClaim.accepted)
        XCTAssertTrue(secondClaim.didAcquireOwnership)
        XCTAssertEqual(secondClaim.activeLease?.hostId, ObjectIdentifier(secondHost))
    }
}
