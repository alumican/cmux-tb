import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class BrowserLifecycleExecutorTests: XCTestCase {
    func testVisibleBrowserWithoutReadyAnchorPlansWaitForAnchor() {
        let current = makeCurrentBrowserRecord(
            state: .awaitingAnchor,
            residency: .detachedRetained,
            activeWindowMembership: false,
            desiredActive: true,
            responderEligible: false,
            accessibilityParticipation: false
        )
        let desired = makeDesiredBrowserRecord(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            targetState: .awaitingAnchor,
            targetResidency: .visibleInActiveWindow,
            targetVisible: true,
            targetActive: true,
            targetResponderEligible: true,
            targetAccessibilityParticipation: true,
            requiresCurrentGenerationAnchor: true,
            anchorReadyForVisibility: false
        )

        let plan = BrowserLifecycleExecutor.makePlan(currentRecords: [current], desiredRecords: [desired])

        XCTAssertEqual(plan.counts.panelCount, 1)
        XCTAssertEqual(plan.counts.waitForAnchorCount, 1)
        XCTAssertEqual(plan.records.first?.action, .waitForAnchor)
    }

    func testSatisfiedVisibleBrowserBindingPlansNoop() {
        let current = makeCurrentBrowserRecord(
            state: .boundVisible,
            residency: .visibleInActiveWindow,
            activeWindowMembership: true,
            desiredActive: true,
            responderEligible: true,
            accessibilityParticipation: true
        )
        let desired = makeDesiredBrowserRecord(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            targetState: .boundVisible,
            targetResidency: .visibleInActiveWindow,
            targetVisible: true,
            targetActive: true,
            targetResponderEligible: true,
            targetAccessibilityParticipation: true,
            requiresCurrentGenerationAnchor: true,
            anchorReadyForVisibility: true
        )
        let binding = makeBinding(
            panelId: current.panelId,
            anchorId: desired.targetAnchorId,
            windowNumber: 41,
            visibleInUI: true,
            containerHidden: false,
            attachedToPortalHost: true,
            guardGeneration: 5
        )

        let plan = BrowserLifecycleExecutor.makePlan(
            currentRecords: [current],
            desiredRecords: [desired],
            currentBindings: [binding]
        )

        XCTAssertEqual(plan.counts.noopCount, 1)
        XCTAssertEqual(plan.records.first?.action, .noop)
        XCTAssertEqual(plan.records.first?.bindingSatisfied, true)
    }

    func testStaleGenerationVisibleBrowserBindingPlansBindVisible() {
        let current = makeCurrentBrowserRecord(
            state: .boundVisible,
            residency: .visibleInActiveWindow,
            activeWindowMembership: true,
            desiredActive: true,
            responderEligible: true,
            accessibilityParticipation: true
        )
        let desired = makeDesiredBrowserRecord(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            targetState: .boundVisible,
            targetResidency: .visibleInActiveWindow,
            targetVisible: true,
            targetActive: true,
            targetResponderEligible: true,
            targetAccessibilityParticipation: true,
            requiresCurrentGenerationAnchor: true,
            anchorReadyForVisibility: true
        )
        let binding = makeBinding(
            panelId: current.panelId,
            anchorId: desired.targetAnchorId,
            windowNumber: 41,
            visibleInUI: true,
            containerHidden: false,
            attachedToPortalHost: true,
            guardGeneration: 4
        )

        let plan = BrowserLifecycleExecutor.makePlan(
            currentRecords: [current],
            desiredRecords: [desired],
            currentBindings: [binding]
        )

        XCTAssertEqual(plan.counts.bindVisibleCount, 1)
        XCTAssertEqual(plan.records.first?.action, .bindVisible)
        XCTAssertEqual(plan.records.first?.bindingSatisfied, false)
    }

    func testVisibleBrowserWithoutBindingStillPlansBindVisible() {
        let current = makeCurrentBrowserRecord(
            state: .boundVisible,
            residency: .visibleInActiveWindow,
            activeWindowMembership: true,
            desiredActive: true,
            responderEligible: true,
            accessibilityParticipation: true
        )
        let desired = makeDesiredBrowserRecord(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            targetState: .boundVisible,
            targetResidency: .visibleInActiveWindow,
            targetVisible: true,
            targetActive: true,
            targetResponderEligible: true,
            targetAccessibilityParticipation: true,
            requiresCurrentGenerationAnchor: true,
            anchorReadyForVisibility: true
        )

        let plan = BrowserLifecycleExecutor.makePlan(
            currentRecords: [current],
            desiredRecords: [desired],
            currentBindings: []
        )

        XCTAssertEqual(plan.counts.bindVisibleCount, 1)
        XCTAssertEqual(plan.records.first?.action, .bindVisible)
        XCTAssertEqual(plan.records.first?.bindingPresent, false)
        XCTAssertEqual(plan.records.first?.bindingSatisfied, false)
    }

    func testHiddenBrowserPlansDetachRetained() {
        let current = makeCurrentBrowserRecord(
            state: .boundHidden,
            residency: .visibleInActiveWindow,
            activeWindowMembership: true,
            desiredActive: false,
            responderEligible: false,
            accessibilityParticipation: true
        )
        let desired = makeDesiredBrowserRecord(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            targetState: .parked,
            targetResidency: .detachedRetained,
            targetVisible: false,
            targetActive: false,
            targetResponderEligible: false,
            targetAccessibilityParticipation: false,
            requiresCurrentGenerationAnchor: false,
            anchorReadyForVisibility: false
        )

        let plan = BrowserLifecycleExecutor.makePlan(currentRecords: [current], desiredRecords: [desired])

        XCTAssertEqual(plan.counts.moveToDetachedRetainedCount, 1)
        XCTAssertEqual(plan.records.first?.action, .moveToDetachedRetained)
    }

    func testRuntimeTargetRequiresCurrentGenerationAnchor() {
        let desired = makeDesiredBrowserRecord(
            targetState: .boundVisible,
            targetResidency: .visibleInActiveWindow,
            targetVisible: true,
            targetActive: true,
            targetResponderEligible: true,
            targetAccessibilityParticipation: true,
            requiresCurrentGenerationAnchor: true,
            anchorReadyForVisibility: true
        )

        let target = BrowserLifecycleExecutor.runtimeTarget(
            desiredRecord: desired,
            fallbackVisible: true,
            fallbackActive: true,
            expectedAnchorId: desired.targetAnchorId,
            binding: nil
        )

        XCTAssertTrue(target.requiresCurrentGenerationAnchor)
        XCTAssertEqual(target.decision.action, .bindVisible)
    }

    func testTransientRecoveryPlanPreservesVisibleDuringOffWindowReparent() {
        let plan = BrowserLifecycleExecutor.transientRecoveryPlan(
            context: BrowserLifecycleExecutorTransientRecoveryContext(
                reason: .anchorWindowMismatchOffWindowReparent,
                entryVisibleInUI: true,
                containerHidden: false,
                recoveryScheduled: true
            )
        )

        XCTAssertTrue(plan.shouldPreserveVisible)
        XCTAssertFalse(plan.shouldHideContainer)
        XCTAssertFalse(plan.shouldScheduleDeferredFullSynchronize)
    }

    func testTransientRecoveryPlanHidesAndSchedulesForHostBoundsNotReady() {
        let plan = BrowserLifecycleExecutor.transientRecoveryPlan(
            context: BrowserLifecycleExecutorTransientRecoveryContext(
                reason: .hostBoundsNotReady,
                entryVisibleInUI: false,
                containerHidden: false,
                recoveryScheduled: false
            )
        )

        XCTAssertFalse(plan.shouldPreserveVisible)
        XCTAssertTrue(plan.shouldHideContainer)
        XCTAssertTrue(plan.shouldScheduleDeferredFullSynchronize)
    }

    func testPresentationPlanShowsChromeOnlyWhenVisibleAndNotHidden() {
        let visible = BrowserLifecycleExecutor.presentationPlan(
            targetVisible: true,
            shouldHideContainer: false
        )
        let visibleApplication = BrowserLifecycleExecutor.presentationApplicationPlan(
            presentation: visible,
            containerHidden: true,
            paneTopChromeHeight: 28
        )
        XCTAssertTrue(visible.shouldShowPaneTopChrome)
        XCTAssertTrue(visible.shouldShowSearchOverlay)
        XCTAssertTrue(visible.shouldShowDropZone)
        XCTAssertTrue(visibleApplication.shouldRevealContainer)
        XCTAssertEqual(visibleApplication.paneTopChromeHeight, 28)
        XCTAssertTrue(visibleApplication.shouldRefreshForReveal)

        let hidden = BrowserLifecycleExecutor.presentationPlan(
            targetVisible: true,
            shouldHideContainer: true
        )
        let hiddenApplication = BrowserLifecycleExecutor.presentationApplicationPlan(
            presentation: hidden,
            containerHidden: false,
            paneTopChromeHeight: 28
        )
        XCTAssertFalse(hidden.shouldShowPaneTopChrome)
        XCTAssertFalse(hidden.shouldShowSearchOverlay)
        XCTAssertFalse(hidden.shouldShowDropZone)
        XCTAssertTrue(hiddenApplication.shouldHideContainer)
        XCTAssertEqual(hiddenApplication.paneTopChromeHeight, 0)
        XCTAssertFalse(hiddenApplication.shouldRefreshForReveal)
    }

    func testRuntimeApplicationPlanForDestroyDetachesWebView() {
        let target = BrowserLifecycleExecutorRuntimeTarget(
            targetResidency: .destroyed,
            targetVisible: false,
            targetActive: false,
            targetWindowNumber: nil,
            targetAnchorId: nil,
            requiresCurrentGenerationAnchor: false,
            anchorReadyForVisibility: false,
            decision: BrowserLifecycleExecutorRuntimeDecision(
                action: .destroy,
                shouldSynchronizeVisibleGeometry: false
            )
        )

        let plan = BrowserLifecycleExecutor.runtimeApplicationPlan(target: target)

        XCTAssertTrue(plan.shouldDetachWebView)
        XCTAssertFalse(plan.shouldBindVisible)
        XCTAssertFalse(plan.shouldUpdateEntryVisibility)
    }

    func testSynchronizationGeometryStateClampsVisibleFrameToHostBounds() {
        let state = BrowserLifecycleExecutor.synchronizationGeometryState(
            entryVisibleInUI: true,
            frameInHost: CGRect(x: -20, y: 10, width: 140, height: 80),
            hostBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            anchorHidden: false
        )

        XCTAssertTrue(state.hostBoundsReady)
        XCTAssertTrue(state.hasFiniteFrame)
        XCTAssertTrue(state.frameWasClamped)
        XCTAssertEqual(state.targetFrame, CGRect(x: 0, y: 10, width: 100, height: 80))
        XCTAssertFalse(state.tinyFrame)
        XCTAssertFalse(state.outsideHostBounds)
        XCTAssertFalse(state.shouldHideContainer)
        XCTAssertNil(state.transientRecoveryReason)
    }

    func testSynchronizationGeometryStateMarksOutsideBoundsVisibleBrowserTransient() {
        let state = BrowserLifecycleExecutor.synchronizationGeometryState(
            entryVisibleInUI: true,
            frameInHost: CGRect(x: 160, y: 20, width: 40, height: 40),
            hostBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            anchorHidden: false
        )

        XCTAssertTrue(state.hostBoundsReady)
        XCTAssertTrue(state.hasFiniteFrame)
        XCTAssertTrue(state.outsideHostBounds)
        XCTAssertTrue(state.shouldHideContainer)
        XCTAssertEqual(state.transientRecoveryReason, .outsideHostBounds)
        XCTAssertEqual(state.targetFrame, CGRect(x: 160, y: 20, width: 40, height: 40))
    }

    func testSynchronizationGeometryStateTreatsSmallHostBoundsAsNotReady() {
        let state = BrowserLifecycleExecutor.synchronizationGeometryState(
            entryVisibleInUI: true,
            frameInHost: CGRect(x: 10, y: 10, width: 50, height: 50),
            hostBounds: CGRect(x: 0, y: 0, width: 1, height: 100),
            anchorHidden: false
        )

        XCTAssertFalse(state.hostBoundsReady)
        XCTAssertTrue(state.hasFiniteFrame)
        XCTAssertEqual(state.targetFrame, CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    func testFrameApplicationPlanUpdatesFrameAndBoundsWhenTargetChanges() {
        let plan = BrowserLifecycleExecutor.frameApplicationPlan(
            oldFrame: CGRect(x: 0, y: 0, width: 60, height: 40),
            currentBounds: CGRect(x: 0, y: 0, width: 55, height: 35),
            targetFrame: CGRect(x: 10, y: 12, width: 100, height: 80)
        )

        XCTAssertTrue(plan.shouldUpdateFrame)
        XCTAssertTrue(plan.shouldNormalizeBounds)
        XCTAssertEqual(plan.expectedContainerBounds, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testFrameApplicationPlanSkipsApproximateFrameAndBoundsMatch() {
        let plan = BrowserLifecycleExecutor.frameApplicationPlan(
            oldFrame: CGRect(x: 10.2, y: 11.9, width: 100.1, height: 79.8),
            currentBounds: CGRect(x: 0, y: 0, width: 100.2, height: 80.1),
            targetFrame: CGRect(x: 10, y: 12, width: 100, height: 80)
        )

        XCTAssertFalse(plan.shouldUpdateFrame)
        XCTAssertFalse(plan.shouldNormalizeBounds)
        XCTAssertEqual(plan.expectedContainerBounds, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testWebFrameNormalizationPlanRequestsNormalizeWhenWebFrameOverflowsContainer() {
        let plan = BrowserLifecycleExecutor.webFrameNormalizationPlan(
            currentWebFrame: CGRect(x: 0, y: 0, width: 120, height: 90),
            containerBounds: CGRect(x: 0, y: 0, width: 100, height: 80)
        )

        XCTAssertTrue(plan.shouldNormalizeWebFrame)
        XCTAssertEqual(plan.normalizedWebFrame, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testWebFrameNormalizationPlanSkipsNormalizeWhenWebFrameFitsContainer() {
        let plan = BrowserLifecycleExecutor.webFrameNormalizationPlan(
            currentWebFrame: CGRect(x: 0, y: 0, width: 100, height: 80),
            containerBounds: CGRect(x: 0, y: 0, width: 100, height: 80)
        )

        XCTAssertFalse(plan.shouldNormalizeWebFrame)
        XCTAssertEqual(plan.normalizedWebFrame, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testVisibleSyncPlanPreservesVisibleDuringScheduledTransientGeometryLoss() {
        let presentation = BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: true,
            shouldRevealContainer: false,
            paneTopChromeHeight: 0,
            shouldShowSearchOverlay: false,
            shouldShowDropZone: false,
            shouldRefreshForReveal: false
        )
        let transient = BrowserLifecycleExecutorTransientRecoveryPlan(
            shouldPreserveVisible: true,
            shouldHideContainer: false,
            shouldClearPaneTopChrome: false,
            shouldClearSearchOverlay: false,
            shouldClearDropZone: false,
            shouldResetRecoveryState: false,
            shouldScheduleDeferredFullSynchronize: true
        )

        let plan = BrowserLifecycleExecutor.visibleSyncPlan(
            presentationApplicationPlan: presentation,
            transientRecoveryPlan: transient,
            transientRecoveryReason: .outsideHostBounds,
            forcePresentationRefresh: false,
            hasPendingRefreshReasons: true,
            geometryStateShouldHideContainer: true
        )

        XCTAssertTrue(plan.shouldPreserveVisibleOnTransientGeometry)
        XCTAssertFalse(plan.shouldApplyPresentationApplicationPlan)
        XCTAssertTrue(plan.shouldApplyTransientRecoveryPlan)
        XCTAssertFalse(plan.shouldTrackVisibleEntry)
        XCTAssertFalse(plan.shouldRefreshHostedPresentation)
    }

    func testVisibleSyncPlanRefreshesVisibleHostedPresentationForAnchorDelta() {
        let presentation = BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: false,
            shouldRevealContainer: false,
            paneTopChromeHeight: 32,
            shouldShowSearchOverlay: true,
            shouldShowDropZone: true,
            shouldRefreshForReveal: false
        )

        let plan = BrowserLifecycleExecutor.visibleSyncPlan(
            presentationApplicationPlan: presentation,
            transientRecoveryPlan: nil,
            transientRecoveryReason: nil,
            forcePresentationRefresh: true,
            hasPendingRefreshReasons: false,
            geometryStateShouldHideContainer: false
        )

        XCTAssertFalse(plan.shouldPreserveVisibleOnTransientGeometry)
        XCTAssertTrue(plan.shouldApplyPresentationApplicationPlan)
        XCTAssertTrue(plan.shouldTrackVisibleEntry)
        XCTAssertTrue(plan.shouldAppendAnchorRefreshReason)
        XCTAssertTrue(plan.shouldRefreshHostedPresentation)
    }

    func testVisibleSyncPlanTracksVisibleEntryWithoutTransientLoss() {
        let presentation = BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: false,
            shouldRevealContainer: true,
            paneTopChromeHeight: 32,
            shouldShowSearchOverlay: true,
            shouldShowDropZone: true,
            shouldRefreshForReveal: true
        )

        let plan = BrowserLifecycleExecutor.visibleSyncPlan(
            presentationApplicationPlan: presentation,
            transientRecoveryPlan: nil,
            transientRecoveryReason: nil,
            forcePresentationRefresh: false,
            hasPendingRefreshReasons: true,
            geometryStateShouldHideContainer: false
        )

        XCTAssertFalse(plan.shouldApplyTransientRecoveryPlan)
        XCTAssertTrue(plan.shouldTrackVisibleEntry)
        XCTAssertTrue(plan.shouldRefreshHostedPresentation)
    }

    func testHostedRefreshPlanIncludesFrameAndWebFrameReasonsForVisibleContent() {
        let visibleSyncPlan = BrowserLifecycleExecutorVisibleSyncPlan(
            shouldPreserveVisibleOnTransientGeometry: false,
            shouldApplyPresentationApplicationPlan: true,
            shouldApplyTransientRecoveryPlan: false,
            shouldTrackVisibleEntry: true,
            shouldAppendAnchorRefreshReason: false,
            shouldRefreshHostedPresentation: false
        )
        let framePlan = BrowserLifecycleExecutorFrameApplicationPlan(
            shouldUpdateFrame: true,
            shouldNormalizeBounds: false,
            expectedContainerBounds: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        let webFramePlan = BrowserLifecycleExecutorWebFrameNormalizationPlan(
            shouldNormalizeWebFrame: true,
            normalizedWebFrame: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        let presentationPlan = BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: false,
            shouldRevealContainer: false,
            paneTopChromeHeight: 32,
            shouldShowSearchOverlay: true,
            shouldShowDropZone: true,
            shouldRefreshForReveal: false
        )

        let plan = BrowserLifecycleExecutor.hostedRefreshPlan(
            visibleSyncPlan: visibleSyncPlan,
            frameApplicationPlan: framePlan,
            webFrameNormalizationPlan: webFramePlan,
            presentationApplicationPlan: presentationPlan
        )

        XCTAssertEqual(plan.reasons, [.frame, .webFrame])
        XCTAssertTrue(plan.shouldRefreshHostedPresentation)
    }

    func testHostedRefreshPlanStaysEmptyWhenContainerShouldHide() {
        let visibleSyncPlan = BrowserLifecycleExecutorVisibleSyncPlan(
            shouldPreserveVisibleOnTransientGeometry: false,
            shouldApplyPresentationApplicationPlan: true,
            shouldApplyTransientRecoveryPlan: false,
            shouldTrackVisibleEntry: false,
            shouldAppendAnchorRefreshReason: true,
            shouldRefreshHostedPresentation: true
        )
        let framePlan = BrowserLifecycleExecutorFrameApplicationPlan(
            shouldUpdateFrame: true,
            shouldNormalizeBounds: true,
            expectedContainerBounds: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        let webFramePlan = BrowserLifecycleExecutorWebFrameNormalizationPlan(
            shouldNormalizeWebFrame: true,
            normalizedWebFrame: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        let presentationPlan = BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: true,
            shouldRevealContainer: false,
            paneTopChromeHeight: 0,
            shouldShowSearchOverlay: false,
            shouldShowDropZone: false,
            shouldRefreshForReveal: false
        )

        let plan = BrowserLifecycleExecutor.hostedRefreshPlan(
            visibleSyncPlan: visibleSyncPlan,
            frameApplicationPlan: framePlan,
            webFrameNormalizationPlan: webFramePlan,
            presentationApplicationPlan: presentationPlan
        )

        XCTAssertEqual(plan.reasons, [])
        XCTAssertFalse(plan.shouldRefreshHostedPresentation)
    }

    private func makeCurrentBrowserRecord(
        panelId: UUID = UUID(),
        workspaceId: UUID = UUID(),
        state: PanelLifecycleState,
        residency: PanelResidency,
        activeWindowMembership: Bool,
        desiredActive: Bool,
        responderEligible: Bool,
        accessibilityParticipation: Bool
    ) -> PanelLifecycleRecordSnapshot {
        PanelLifecycleRecordSnapshot(
            panelId: panelId,
            workspaceId: workspaceId,
            paneId: UUID(),
            tabId: UUID(),
            panelType: .browser,
            generation: 5,
            state: state,
            residency: residency,
            mountedWorkspace: true,
            selectedWorkspace: desiredActive,
            retiringWorkspace: false,
            selectedInPane: true,
            desiredVisible: activeWindowMembership,
            desiredActive: desiredActive,
            activeWindowMembership: activeWindowMembership,
            responderEligible: responderEligible,
            accessibilityParticipation: accessibilityParticipation,
            backendProfile: PanelLifecycleShadowMapper.backendProfile(for: .browser),
            anchor: nil
        )
    }

    private func makeDesiredBrowserRecord(
        panelId: UUID = UUID(),
        workspaceId: UUID = UUID(),
        targetState: PanelLifecycleState,
        targetResidency: PanelResidency,
        targetVisible: Bool,
        targetActive: Bool,
        targetResponderEligible: Bool,
        targetAccessibilityParticipation: Bool,
        requiresCurrentGenerationAnchor: Bool,
        anchorReadyForVisibility: Bool
    ) -> PanelLifecycleDesiredRecordSnapshot {
        PanelLifecycleDesiredRecordSnapshot(
            panelId: panelId,
            workspaceId: workspaceId,
            panelType: .browser,
            generation: 5,
            targetState: targetState,
            targetResidency: targetResidency,
            targetVisible: targetVisible,
            targetActive: targetActive,
            targetWindowNumber: targetVisible ? 41 : nil,
            targetAnchorId: targetVisible ? UUID() : nil,
            targetResponderEligible: targetResponderEligible,
            targetAccessibilityParticipation: targetAccessibilityParticipation,
            requiresCurrentGenerationAnchor: requiresCurrentGenerationAnchor,
            anchorReadyForVisibility: anchorReadyForVisibility
        )
    }

    private func makeBinding(
        panelId: UUID,
        anchorId: UUID? = UUID(),
        windowNumber: Int?,
        visibleInUI: Bool,
        containerHidden: Bool,
        attachedToPortalHost: Bool,
        guardGeneration: UInt64?
    ) -> BrowserLifecycleExecutorBindingSnapshot {
        BrowserLifecycleExecutorBindingSnapshot(
            panelId: panelId,
            anchorId: anchorId,
            windowNumber: windowNumber,
            anchorWindowNumber: windowNumber,
            visibleInUI: visibleInUI,
            containerHidden: containerHidden,
            attachedToPortalHost: attachedToPortalHost,
            zPriority: 0,
            guardGeneration: guardGeneration
        )
    }
}
