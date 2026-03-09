import CoreGraphics
import Foundation

enum BrowserLifecycleExecutorAction: String, Codable, Sendable {
    case noop
    case waitForAnchor
    case bindVisible
    case moveToDetachedRetained
    case moveToParkedOffscreen
    case destroy
}

struct BrowserLifecycleExecutorRecordSnapshot: Codable, Sendable {
    let panelId: UUID
    let workspaceId: UUID
    let generation: UInt64
    let action: BrowserLifecycleExecutorAction
    let currentState: PanelLifecycleState
    let targetState: PanelLifecycleState
    let currentResidency: PanelResidency
    let targetResidency: PanelResidency
    let currentVisible: Bool
    let targetVisible: Bool
    let currentActive: Bool
    let targetActive: Bool
    let requiresCurrentGenerationAnchor: Bool
    let targetWindowNumber: Int?
    let targetAnchorId: UUID?
    let anchorReadyForVisibility: Bool
    let bindingPresent: Bool
    let bindingSatisfied: Bool
    let bindingAnchorId: UUID?
    let bindingWindowNumber: Int?
    let bindingVisibleInUI: Bool?
    let bindingContainerHidden: Bool?
    let bindingAttachedToPortalHost: Bool?
    let bindingGeneration: UInt64?
}

struct BrowserLifecycleExecutorBindingSnapshot: Codable, Sendable {
    let panelId: UUID
    let anchorId: UUID?
    let windowNumber: Int?
    let anchorWindowNumber: Int?
    let visibleInUI: Bool
    let containerHidden: Bool
    let attachedToPortalHost: Bool
    let zPriority: Int
    let guardGeneration: UInt64?
}

struct BrowserLifecycleExecutorBindingCounts: Codable, Sendable {
    let panelCount: Int
    let visibleEntryCount: Int
    let hiddenEntryCount: Int
    let attachedEntryCount: Int
    let currentGenerationCount: Int
}

struct BrowserLifecycleExecutorPlanCounts: Codable, Sendable {
    let panelCount: Int
    let noopCount: Int
    let waitForAnchorCount: Int
    let bindVisibleCount: Int
    let moveToDetachedRetainedCount: Int
    let moveToParkedOffscreenCount: Int
    let destroyCount: Int
}

struct BrowserLifecycleExecutorPlanSnapshot: Codable, Sendable {
    let counts: BrowserLifecycleExecutorPlanCounts
    let bindingCounts: BrowserLifecycleExecutorBindingCounts
    let bindings: [BrowserLifecycleExecutorBindingSnapshot]
    let records: [BrowserLifecycleExecutorRecordSnapshot]
}

struct BrowserLifecycleExecutorRuntimeDecision: Sendable {
    let action: BrowserLifecycleExecutorAction
    let shouldSynchronizeVisibleGeometry: Bool
}

struct BrowserLifecycleExecutorRuntimeTarget: Sendable {
    let targetResidency: PanelResidency
    let targetVisible: Bool
    let targetActive: Bool
    let targetWindowNumber: Int?
    let targetAnchorId: UUID?
    let requiresCurrentGenerationAnchor: Bool
    let anchorReadyForVisibility: Bool
    let decision: BrowserLifecycleExecutorRuntimeDecision

    var shouldMountLiveAnchor: Bool {
        targetResidency == .visibleInActiveWindow
    }
}

struct BrowserLifecycleExecutorRuntimeApplicationPlan: Sendable {
    let decision: BrowserLifecycleExecutorRuntimeDecision
    let shouldBindVisible: Bool
    let shouldSynchronizeForAnchor: Bool
    let shouldUpdateEntryVisibility: Bool
    let entryVisibleInUI: Bool
    let shouldHideWebView: Bool
    let shouldDetachWebView: Bool
}

enum BrowserLifecycleExecutorTransientRecoveryReason: String, Sendable {
    case missingAnchorOrWindow
    case anchorWindowMismatch
    case anchorWindowMismatchOffWindowReparent
    case hostBoundsNotReady
    case anchorHidden
    case nonFiniteFrame
    case outsideHostBounds
    case tinyFrame
}

struct BrowserLifecycleExecutorTransientRecoveryContext: Sendable {
    let reason: BrowserLifecycleExecutorTransientRecoveryReason
    let entryVisibleInUI: Bool
    let containerHidden: Bool
    let recoveryScheduled: Bool
}

struct BrowserLifecycleExecutorTransientRecoveryPlan: Sendable {
    let shouldPreserveVisible: Bool
    let shouldHideContainer: Bool
    let shouldClearPaneTopChrome: Bool
    let shouldClearSearchOverlay: Bool
    let shouldClearDropZone: Bool
    let shouldResetRecoveryState: Bool
    let shouldScheduleDeferredFullSynchronize: Bool
}

struct BrowserLifecycleExecutorPresentationPlan: Sendable {
    let shouldHideContainer: Bool
    let shouldShowPaneTopChrome: Bool
    let shouldShowSearchOverlay: Bool
    let shouldShowDropZone: Bool
}

struct BrowserLifecycleExecutorPresentationApplicationPlan: Sendable {
    let shouldHideContainer: Bool
    let shouldRevealContainer: Bool
    let paneTopChromeHeight: CGFloat
    let shouldShowSearchOverlay: Bool
    let shouldShowDropZone: Bool
    let shouldRefreshForReveal: Bool
}

struct BrowserLifecycleExecutorSynchronizationGeometryState: Sendable {
    let hostBoundsReady: Bool
    let hasFiniteFrame: Bool
    let targetFrame: CGRect
    let frameWasClamped: Bool
    let tinyFrame: Bool
    let outsideHostBounds: Bool
    let shouldHideContainer: Bool
    let transientRecoveryReason: BrowserLifecycleExecutorTransientRecoveryReason?
}

struct BrowserLifecycleExecutorFrameApplicationPlan: Sendable {
    let shouldUpdateFrame: Bool
    let shouldNormalizeBounds: Bool
    let expectedContainerBounds: CGRect
}

struct BrowserLifecycleExecutorWebFrameNormalizationPlan: Sendable {
    let shouldNormalizeWebFrame: Bool
    let normalizedWebFrame: CGRect
}

struct BrowserLifecycleExecutorVisibleSyncPlan: Sendable {
    let shouldPreserveVisibleOnTransientGeometry: Bool
    let shouldApplyPresentationApplicationPlan: Bool
    let shouldApplyTransientRecoveryPlan: Bool
    let shouldTrackVisibleEntry: Bool
    let shouldAppendAnchorRefreshReason: Bool
    let shouldRefreshHostedPresentation: Bool
}

enum BrowserLifecycleExecutorHostedRefreshReason: String, Sendable {
    case frame
    case bounds
    case webFrame
    case reveal
    case anchor
}

struct BrowserLifecycleExecutorHostedRefreshPlan: Sendable {
    let reasons: [BrowserLifecycleExecutorHostedRefreshReason]

    var shouldRefreshHostedPresentation: Bool {
        !reasons.isEmpty
    }
}

struct BrowserLifecycleExecutorVisibleApplicationPlan: Sendable {
    let shouldPreserveVisibleOnTransientGeometry: Bool
    let shouldApplyPresentationApplicationPlan: Bool
    let transientRecoveryPlan: BrowserLifecycleExecutorTransientRecoveryPlan?
    let transientRecoveryReason: BrowserLifecycleExecutorTransientRecoveryReason?
    let shouldTrackVisibleEntry: Bool
    let hostedRefreshPlan: BrowserLifecycleExecutorHostedRefreshPlan
}

enum BrowserLifecycleExecutor {
    private static func bindingMatchesWindow(
        _ binding: BrowserLifecycleExecutorBindingSnapshot,
        windowNumber: Int?
    ) -> Bool {
        guard let windowNumber else { return false }
        return binding.windowNumber == windowNumber || binding.anchorWindowNumber == windowNumber
    }

    private static func anchorSnapshot(
        current: PanelLifecycleRecordSnapshot,
        binding: BrowserLifecycleExecutorBindingSnapshot
    ) -> PanelLifecycleAnchorSnapshot? {
        if let anchor = current.anchor {
            let windowNumber = anchor.windowNumber ?? binding.anchorWindowNumber ?? binding.windowNumber
            return PanelLifecycleAnchorSnapshot(
                anchorId: anchor.anchorId,
                anchorGeneration: anchor.anchorGeneration,
                windowNumber: windowNumber,
                hasSuperview: anchor.hasSuperview,
                attachedToWindow: anchor.attachedToWindow || windowNumber != nil,
                hidden: anchor.hidden && (!binding.visibleInUI || binding.containerHidden),
                geometryRevision: anchor.geometryRevision,
                source: anchor.source
            )
        }

        guard let anchorId = binding.anchorId else { return nil }
        let windowNumber = binding.anchorWindowNumber ?? binding.windowNumber
        return PanelLifecycleAnchorSnapshot(
            anchorId: anchorId,
            anchorGeneration: binding.guardGeneration ?? current.generation,
            windowNumber: windowNumber,
            hasSuperview: binding.attachedToPortalHost,
            attachedToWindow: windowNumber != nil,
            hidden: !binding.visibleInUI || binding.containerHidden,
            geometryRevision: 0,
            source: "binding"
        )
    }

    static func currentRecord(
        _ current: PanelLifecycleRecordSnapshot,
        applying binding: BrowserLifecycleExecutorBindingSnapshot?,
        activeWindowNumber: Int?
    ) -> PanelLifecycleRecordSnapshot {
        guard current.panelType == .browser, let binding else { return current }

        let visibleInActiveWindow =
            bindingMatchesWindow(binding, windowNumber: activeWindowNumber) &&
            binding.visibleInUI &&
            !binding.containerHidden &&
            binding.attachedToPortalHost

        if visibleInActiveWindow {
            let state: PanelLifecycleState
            if current.retiringWorkspace && current.desiredVisible && current.mountedWorkspace {
                state = .handoff
            } else {
                state = .boundVisible
            }
            return PanelLifecycleRecordSnapshot(
                panelId: current.panelId,
                workspaceId: current.workspaceId,
                paneId: current.paneId,
                tabId: current.tabId,
                panelType: current.panelType,
                generation: current.generation,
                state: state,
                residency: .visibleInActiveWindow,
                mountedWorkspace: current.mountedWorkspace,
                selectedWorkspace: current.selectedWorkspace,
                retiringWorkspace: current.retiringWorkspace,
                selectedInPane: current.selectedInPane,
                desiredVisible: current.desiredVisible,
                desiredActive: current.desiredActive,
                activeWindowMembership: true,
                responderEligible: current.desiredActive &&
                    current.backendProfile.focusPolicy == .firstResponder,
                accessibilityParticipation: current.backendProfile.accessibilityPolicy == .activeVisibleTree,
                backendProfile: current.backendProfile,
                anchor: anchorSnapshot(current: current, binding: binding)
            )
        }

        let hiddenInPortal =
            binding.attachedToPortalHost &&
            (!binding.visibleInUI || binding.containerHidden)
        guard hiddenInPortal else { return current }

        let residency: PanelResidency = current.backendProfile.residencyPolicy == .parked
            ? .parkedOffscreen
            : .detachedRetained
        let state: PanelLifecycleState = current.mountedWorkspace ? .boundHidden : .parked
        return PanelLifecycleRecordSnapshot(
            panelId: current.panelId,
            workspaceId: current.workspaceId,
            paneId: current.paneId,
            tabId: current.tabId,
            panelType: current.panelType,
            generation: current.generation,
            state: state,
            residency: residency,
            mountedWorkspace: current.mountedWorkspace,
            selectedWorkspace: current.selectedWorkspace,
            retiringWorkspace: current.retiringWorkspace,
            selectedInPane: current.selectedInPane,
            desiredVisible: current.desiredVisible,
            desiredActive: current.desiredActive,
            activeWindowMembership: false,
            responderEligible: false,
            accessibilityParticipation: false,
            backendProfile: current.backendProfile,
            anchor: anchorSnapshot(current: current, binding: binding)
        )
    }

    static func isCurrentGenerationBoundVisibleReadyForWorkspaceHandoff(
        currentRecord: PanelLifecycleRecordSnapshot,
        desiredRecord: PanelLifecycleDesiredRecordSnapshot,
        binding: BrowserLifecycleExecutorBindingSnapshot?
    ) -> Bool {
        guard currentRecord.panelType == .browser, desiredRecord.panelType == .browser else {
            return false
        }
        guard desiredRecord.targetState == .boundVisible,
              desiredRecord.targetResidency == .visibleInActiveWindow,
              desiredRecord.targetVisible,
              desiredRecord.targetActive else {
            return false
        }

        let runtimeTarget = runtimeTarget(
            desiredRecord: desiredRecord,
            fallbackVisible: currentRecord.desiredVisible,
            fallbackActive: currentRecord.desiredActive,
            expectedAnchorId: desiredRecord.targetAnchorId,
            binding: binding
        )

        return currentRecord.generation == desiredRecord.generation &&
            currentRecord.state == .boundVisible &&
            currentRecord.residency == .visibleInActiveWindow &&
            currentRecord.activeWindowMembership &&
            runtimeTarget.decision.action == .noop
    }

    static func makePlan(
        currentRecords: [PanelLifecycleRecordSnapshot],
        desiredRecords: [PanelLifecycleDesiredRecordSnapshot],
        currentBindings: [BrowserLifecycleExecutorBindingSnapshot] = []
    ) -> BrowserLifecycleExecutorPlanSnapshot {
        let currentByPanelId = Dictionary(
            uniqueKeysWithValues: currentRecords
                .filter { $0.panelType == .browser }
                .map { ($0.panelId, $0) }
        )
        let bindingByPanelId = Dictionary(uniqueKeysWithValues: currentBindings.map { ($0.panelId, $0) })
        let records = desiredRecords.compactMap { desired -> BrowserLifecycleExecutorRecordSnapshot? in
            guard desired.panelType == .browser else { return nil }
            let current = currentByPanelId[desired.panelId] ?? syntheticCurrentRecord(for: desired)
            let binding = bindingByPanelId[desired.panelId]
            let bindingSatisfied = isBindingSatisfied(binding: binding, desired: desired)
            return BrowserLifecycleExecutorRecordSnapshot(
                panelId: current.panelId,
                workspaceId: current.workspaceId,
                generation: desired.generation,
                action: plannedAction(current: current, desired: desired, bindingSatisfied: bindingSatisfied),
                currentState: current.state,
                targetState: desired.targetState,
                currentResidency: current.residency,
                targetResidency: desired.targetResidency,
                currentVisible: current.activeWindowMembership,
                targetVisible: desired.targetVisible,
                currentActive: current.desiredActive,
                targetActive: desired.targetActive,
                requiresCurrentGenerationAnchor: desired.requiresCurrentGenerationAnchor,
                targetWindowNumber: desired.targetWindowNumber,
                targetAnchorId: desired.targetAnchorId,
                anchorReadyForVisibility: desired.anchorReadyForVisibility,
                bindingPresent: binding != nil,
                bindingSatisfied: bindingSatisfied,
                bindingAnchorId: binding?.anchorId,
                bindingWindowNumber: binding?.windowNumber,
                bindingVisibleInUI: binding?.visibleInUI,
                bindingContainerHidden: binding?.containerHidden,
                bindingAttachedToPortalHost: binding?.attachedToPortalHost,
                bindingGeneration: binding?.guardGeneration
            )
        }

        return BrowserLifecycleExecutorPlanSnapshot(
            counts: counts(for: records),
            bindingCounts: bindingCounts(for: currentBindings),
            bindings: currentBindings.sorted { $0.panelId.uuidString < $1.panelId.uuidString },
            records: records
        )
    }

    private static func syntheticCurrentRecord(
        for desired: PanelLifecycleDesiredRecordSnapshot
    ) -> PanelLifecycleRecordSnapshot {
        PanelLifecycleRecordSnapshot(
            panelId: desired.panelId,
            workspaceId: desired.workspaceId,
            paneId: nil,
            tabId: nil,
            panelType: .browser,
            generation: desired.generation,
            state: .closed,
            residency: .destroyed,
            mountedWorkspace: false,
            selectedWorkspace: false,
            retiringWorkspace: false,
            selectedInPane: false,
            desiredVisible: false,
            desiredActive: false,
            activeWindowMembership: false,
            responderEligible: false,
            accessibilityParticipation: false,
            backendProfile: PanelLifecycleShadowMapper.backendProfile(for: .browser),
            anchor: nil
        )
    }

    private static func plannedAction(
        current: PanelLifecycleRecordSnapshot,
        desired: PanelLifecycleDesiredRecordSnapshot,
        bindingSatisfied: Bool
    ) -> BrowserLifecycleExecutorAction {
        _ = current
        if desired.targetVisible {
            if !desired.anchorReadyForVisibility {
                return .waitForAnchor
            }
            return bindingSatisfied ? .noop : .bindVisible
        }

        switch desired.targetResidency {
        case .detachedRetained:
            return isHiddenTargetSatisfied(current: current, desired: desired)
                ? .noop
                : .moveToDetachedRetained
        case .parkedOffscreen:
            return isHiddenTargetSatisfied(current: current, desired: desired)
                ? .noop
                : .moveToParkedOffscreen
        case .destroyed:
            return isHiddenTargetSatisfied(current: current, desired: desired) ? .noop : .destroy
        case .visibleInActiveWindow:
            return desired.anchorReadyForVisibility ? .bindVisible : .waitForAnchor
        }
    }

    private static func isHiddenTargetSatisfied(
        current: PanelLifecycleRecordSnapshot,
        desired: PanelLifecycleDesiredRecordSnapshot
    ) -> Bool {
        current.residency == desired.targetResidency &&
            !current.activeWindowMembership &&
            !current.desiredActive
    }

    private static func counts(
        for records: [BrowserLifecycleExecutorRecordSnapshot]
    ) -> BrowserLifecycleExecutorPlanCounts {
        BrowserLifecycleExecutorPlanCounts(
            panelCount: records.count,
            noopCount: records.filter { $0.action == .noop }.count,
            waitForAnchorCount: records.filter { $0.action == .waitForAnchor }.count,
            bindVisibleCount: records.filter { $0.action == .bindVisible }.count,
            moveToDetachedRetainedCount: records.filter { $0.action == .moveToDetachedRetained }.count,
            moveToParkedOffscreenCount: records.filter { $0.action == .moveToParkedOffscreen }.count,
            destroyCount: records.filter { $0.action == .destroy }.count
        )
    }

    private static func bindingCounts(
        for bindings: [BrowserLifecycleExecutorBindingSnapshot]
    ) -> BrowserLifecycleExecutorBindingCounts {
        BrowserLifecycleExecutorBindingCounts(
            panelCount: bindings.count,
            visibleEntryCount: bindings.filter { $0.visibleInUI }.count,
            hiddenEntryCount: bindings.filter { !$0.visibleInUI || $0.containerHidden }.count,
            attachedEntryCount: bindings.filter { $0.attachedToPortalHost }.count,
            currentGenerationCount: bindings.filter { $0.guardGeneration != nil }.count
        )
    }

    private static func isBindingSatisfied(
        binding: BrowserLifecycleExecutorBindingSnapshot?,
        desired: PanelLifecycleDesiredRecordSnapshot
    ) -> Bool {
        guard let binding else { return false }
        if desired.targetVisible {
            return bindingMatchesWindow(binding, windowNumber: desired.targetWindowNumber) &&
                binding.anchorId == desired.targetAnchorId &&
                binding.visibleInUI &&
                !binding.containerHidden &&
                binding.attachedToPortalHost &&
                (!desired.requiresCurrentGenerationAnchor || binding.guardGeneration == desired.generation)
        }

        switch desired.targetResidency {
        case .parkedOffscreen:
            return !binding.visibleInUI && binding.containerHidden && binding.attachedToPortalHost
        case .detachedRetained, .destroyed:
            return false
        case .visibleInActiveWindow:
            return bindingMatchesWindow(binding, windowNumber: desired.targetWindowNumber) &&
                binding.visibleInUI &&
                !binding.containerHidden &&
                binding.attachedToPortalHost
        }
    }

    static func runtimeTarget(
        desiredRecord: PanelLifecycleDesiredRecordSnapshot?,
        fallbackVisible: Bool,
        fallbackActive: Bool,
        expectedAnchorId: UUID?,
        binding: BrowserLifecycleExecutorBindingSnapshot? = nil
    ) -> BrowserLifecycleExecutorRuntimeTarget {
        let targetVisible = desiredRecord?.targetVisible ?? fallbackVisible
        let targetActive = desiredRecord?.targetActive ?? fallbackActive
        let targetResidency = desiredRecord?.targetResidency
            ?? (targetVisible ? .visibleInActiveWindow : .detachedRetained)
        let targetWindowNumber = desiredRecord?.targetWindowNumber
        let targetAnchorId = desiredRecord?.targetAnchorId ?? (targetVisible ? expectedAnchorId : nil)
        let requiresCurrentGenerationAnchor = desiredRecord?.requiresCurrentGenerationAnchor ?? false
        let anchorReadyForVisibility = desiredRecord?.anchorReadyForVisibility ?? targetVisible
        let bindingSatisfied = desiredRecord.map {
            isBindingSatisfied(binding: binding, desired: $0)
        } ?? false
        let action: BrowserLifecycleExecutorAction
        if targetVisible {
            action = !anchorReadyForVisibility ? .waitForAnchor : (bindingSatisfied ? .noop : .bindVisible)
        } else {
            switch targetResidency {
            case .detachedRetained:
                action = binding == nil ? .noop : .moveToDetachedRetained
            case .parkedOffscreen:
                action = bindingSatisfied ? .noop : .moveToParkedOffscreen
            case .destroyed:
                action = binding == nil ? .noop : .destroy
            case .visibleInActiveWindow:
                action = !anchorReadyForVisibility ? .waitForAnchor : (bindingSatisfied ? .noop : .bindVisible)
            }
        }
        let decision = BrowserLifecycleExecutorRuntimeDecision(
            action: action,
            shouldSynchronizeVisibleGeometry: targetVisible && anchorReadyForVisibility
        )
        return BrowserLifecycleExecutorRuntimeTarget(
            targetResidency: targetResidency,
            targetVisible: targetVisible,
            targetActive: targetActive,
            targetWindowNumber: targetWindowNumber,
            targetAnchorId: targetAnchorId,
            requiresCurrentGenerationAnchor: requiresCurrentGenerationAnchor,
            anchorReadyForVisibility: anchorReadyForVisibility,
            decision: decision
        )
    }

    static func runtimeApplicationPlan(
        target: BrowserLifecycleExecutorRuntimeTarget
    ) -> BrowserLifecycleExecutorRuntimeApplicationPlan {
        switch target.decision.action {
        case .noop:
            return BrowserLifecycleExecutorRuntimeApplicationPlan(
                decision: target.decision,
                shouldBindVisible: false,
                shouldSynchronizeForAnchor: target.decision.shouldSynchronizeVisibleGeometry,
                shouldUpdateEntryVisibility: true,
                entryVisibleInUI: target.targetVisible,
                shouldHideWebView: false,
                shouldDetachWebView: false
            )
        case .waitForAnchor:
            return BrowserLifecycleExecutorRuntimeApplicationPlan(
                decision: target.decision,
                shouldBindVisible: false,
                shouldSynchronizeForAnchor: false,
                shouldUpdateEntryVisibility: true,
                entryVisibleInUI: target.targetVisible,
                shouldHideWebView: false,
                shouldDetachWebView: false
            )
        case .bindVisible:
            return BrowserLifecycleExecutorRuntimeApplicationPlan(
                decision: target.decision,
                shouldBindVisible: true,
                shouldSynchronizeForAnchor: false,
                shouldUpdateEntryVisibility: false,
                entryVisibleInUI: true,
                shouldHideWebView: false,
                shouldDetachWebView: false
            )
        case .moveToDetachedRetained, .moveToParkedOffscreen:
            return BrowserLifecycleExecutorRuntimeApplicationPlan(
                decision: target.decision,
                shouldBindVisible: false,
                shouldSynchronizeForAnchor: false,
                shouldUpdateEntryVisibility: false,
                entryVisibleInUI: false,
                shouldHideWebView: true,
                shouldDetachWebView: false
            )
        case .destroy:
            return BrowserLifecycleExecutorRuntimeApplicationPlan(
                decision: target.decision,
                shouldBindVisible: false,
                shouldSynchronizeForAnchor: false,
                shouldUpdateEntryVisibility: false,
                entryVisibleInUI: false,
                shouldHideWebView: false,
                shouldDetachWebView: true
            )
        }
    }

    static func transientRecoveryPlan(
        context: BrowserLifecycleExecutorTransientRecoveryContext
    ) -> BrowserLifecycleExecutorTransientRecoveryPlan {
        let shouldPreserveVisible =
            context.recoveryScheduled &&
            (context.reason == .anchorWindowMismatchOffWindowReparent ||
                context.reason == .hostBoundsNotReady ||
                context.reason == .anchorHidden ||
                context.reason == .nonFiniteFrame ||
                context.reason == .outsideHostBounds ||
                context.reason == .tinyFrame) &&
            !context.containerHidden
        if shouldPreserveVisible {
            return BrowserLifecycleExecutorTransientRecoveryPlan(
                shouldPreserveVisible: true,
                shouldHideContainer: false,
                shouldClearPaneTopChrome: false,
                shouldClearSearchOverlay: false,
                shouldClearDropZone: true,
                shouldResetRecoveryState: false,
                shouldScheduleDeferredFullSynchronize: false
            )
        }

        let shouldResetRecoveryState = !context.entryVisibleInUI
        let shouldScheduleDeferredFullSynchronize =
            shouldResetRecoveryState && context.reason == .hostBoundsNotReady
        return BrowserLifecycleExecutorTransientRecoveryPlan(
            shouldPreserveVisible: false,
            shouldHideContainer: true,
            shouldClearPaneTopChrome: true,
            shouldClearSearchOverlay: true,
            shouldClearDropZone: true,
            shouldResetRecoveryState: shouldResetRecoveryState,
            shouldScheduleDeferredFullSynchronize: shouldScheduleDeferredFullSynchronize
        )
    }

    static func transientRecoveryReason(
        entryVisibleInUI: Bool,
        anchorHidden: Bool,
        hasFiniteFrame: Bool,
        outsideHostBounds: Bool,
        tinyFrame: Bool
    ) -> BrowserLifecycleExecutorTransientRecoveryReason? {
        guard entryVisibleInUI else { return nil }
        if anchorHidden { return .anchorHidden }
        if !hasFiniteFrame { return .nonFiniteFrame }
        if outsideHostBounds { return .outsideHostBounds }
        if tinyFrame { return .tinyFrame }
        return nil
    }

    static func presentationPlan(
        targetVisible: Bool,
        shouldHideContainer: Bool
    ) -> BrowserLifecycleExecutorPresentationPlan {
        let shouldShowContent = targetVisible && !shouldHideContainer
        return BrowserLifecycleExecutorPresentationPlan(
            shouldHideContainer: shouldHideContainer,
            shouldShowPaneTopChrome: shouldShowContent,
            shouldShowSearchOverlay: shouldShowContent,
            shouldShowDropZone: shouldShowContent
        )
    }

    static func presentationApplicationPlan(
        presentation: BrowserLifecycleExecutorPresentationPlan,
        containerHidden: Bool,
        paneTopChromeHeight: CGFloat
    ) -> BrowserLifecycleExecutorPresentationApplicationPlan {
        BrowserLifecycleExecutorPresentationApplicationPlan(
            shouldHideContainer: presentation.shouldHideContainer,
            shouldRevealContainer: !presentation.shouldHideContainer && containerHidden,
            paneTopChromeHeight: presentation.shouldShowPaneTopChrome ? paneTopChromeHeight : 0,
            shouldShowSearchOverlay: presentation.shouldShowSearchOverlay,
            shouldShowDropZone: presentation.shouldShowDropZone,
            shouldRefreshForReveal: !presentation.shouldHideContainer &&
                containerHidden &&
                presentation.shouldShowPaneTopChrome
        )
    }

    static func synchronizationGeometryState(
        entryVisibleInUI: Bool,
        frameInHost: CGRect,
        hostBounds: CGRect,
        anchorHidden: Bool
    ) -> BrowserLifecycleExecutorSynchronizationGeometryState {
        let hasFiniteHostBounds =
            hostBounds.origin.x.isFinite &&
            hostBounds.origin.y.isFinite &&
            hostBounds.size.width.isFinite &&
            hostBounds.size.height.isFinite
        let hostBoundsReady = hasFiniteHostBounds && hostBounds.width > 1 && hostBounds.height > 1
        let hasFiniteFrame =
            frameInHost.origin.x.isFinite &&
            frameInHost.origin.y.isFinite &&
            frameInHost.size.width.isFinite &&
            frameInHost.size.height.isFinite
        let clampedFrame = frameInHost.intersection(hostBounds)
        let hasVisibleIntersection =
            !clampedFrame.isNull &&
            clampedFrame.width > 1 &&
            clampedFrame.height > 1
        let targetFrame = hasVisibleIntersection ? clampedFrame : frameInHost
        let frameWasClamped = hasFiniteFrame && targetFrame != frameInHost
        let tinyFrame = targetFrame.width <= 1 || targetFrame.height <= 1
        let outsideHostBounds = !hasVisibleIntersection
        let shouldHideContainer =
            !entryVisibleInUI ||
            anchorHidden ||
            tinyFrame ||
            !hasFiniteFrame ||
            outsideHostBounds
        return BrowserLifecycleExecutorSynchronizationGeometryState(
            hostBoundsReady: hostBoundsReady,
            hasFiniteFrame: hasFiniteFrame,
            targetFrame: targetFrame,
            frameWasClamped: frameWasClamped,
            tinyFrame: tinyFrame,
            outsideHostBounds: outsideHostBounds,
            shouldHideContainer: shouldHideContainer,
            transientRecoveryReason: transientRecoveryReason(
                entryVisibleInUI: entryVisibleInUI,
                anchorHidden: anchorHidden,
                hasFiniteFrame: hasFiniteFrame,
                outsideHostBounds: outsideHostBounds,
                tinyFrame: tinyFrame
            )
        )
    }

    static func frameApplicationPlan(
        oldFrame: CGRect,
        currentBounds: CGRect,
        targetFrame: CGRect
    ) -> BrowserLifecycleExecutorFrameApplicationPlan {
        let expectedContainerBounds = CGRect(origin: .zero, size: targetFrame.size)
        return BrowserLifecycleExecutorFrameApplicationPlan(
            shouldUpdateFrame: !rectApproximatelyEqual(oldFrame, targetFrame),
            shouldNormalizeBounds: !rectApproximatelyEqual(currentBounds, expectedContainerBounds),
            expectedContainerBounds: expectedContainerBounds
        )
    }

    static func webFrameNormalizationPlan(
        currentWebFrame: CGRect,
        containerBounds: CGRect
    ) -> BrowserLifecycleExecutorWebFrameNormalizationPlan {
        BrowserLifecycleExecutorWebFrameNormalizationPlan(
            shouldNormalizeWebFrame: frameExtendsOutsideBounds(currentWebFrame, bounds: containerBounds),
            normalizedWebFrame: containerBounds
        )
    }

    static func visibleSyncPlan(
        presentationApplicationPlan: BrowserLifecycleExecutorPresentationApplicationPlan,
        transientRecoveryPlan: BrowserLifecycleExecutorTransientRecoveryPlan?,
        transientRecoveryReason: BrowserLifecycleExecutorTransientRecoveryReason?,
        forcePresentationRefresh: Bool,
        hasPendingRefreshReasons: Bool,
        geometryStateShouldHideContainer: Bool
    ) -> BrowserLifecycleExecutorVisibleSyncPlan {
        let shouldPreserveVisibleOnTransientGeometry =
            transientRecoveryPlan?.shouldPreserveVisible == true &&
            geometryStateShouldHideContainer
        let shouldAppendAnchorRefreshReason = forcePresentationRefresh
        let shouldRefreshHostedPresentation =
            !presentationApplicationPlan.shouldHideContainer &&
            (
                hasPendingRefreshReasons ||
                shouldAppendAnchorRefreshReason ||
                presentationApplicationPlan.shouldRefreshForReveal
            )
        return BrowserLifecycleExecutorVisibleSyncPlan(
            shouldPreserveVisibleOnTransientGeometry: shouldPreserveVisibleOnTransientGeometry,
            shouldApplyPresentationApplicationPlan: !shouldPreserveVisibleOnTransientGeometry,
            shouldApplyTransientRecoveryPlan:
                transientRecoveryReason != nil &&
                presentationApplicationPlan.shouldHideContainer,
            shouldTrackVisibleEntry: transientRecoveryReason == nil,
            shouldAppendAnchorRefreshReason: shouldAppendAnchorRefreshReason,
            shouldRefreshHostedPresentation: shouldRefreshHostedPresentation
        )
    }

    static func hostedRefreshPlan(
        visibleSyncPlan: BrowserLifecycleExecutorVisibleSyncPlan,
        frameApplicationPlan: BrowserLifecycleExecutorFrameApplicationPlan,
        webFrameNormalizationPlan: BrowserLifecycleExecutorWebFrameNormalizationPlan,
        presentationApplicationPlan: BrowserLifecycleExecutorPresentationApplicationPlan
    ) -> BrowserLifecycleExecutorHostedRefreshPlan {
        guard !presentationApplicationPlan.shouldHideContainer else {
            return BrowserLifecycleExecutorHostedRefreshPlan(reasons: [])
        }

        var reasons: [BrowserLifecycleExecutorHostedRefreshReason] = []
        if frameApplicationPlan.shouldUpdateFrame {
            reasons.append(.frame)
        }
        if frameApplicationPlan.shouldNormalizeBounds {
            reasons.append(.bounds)
        }
        if webFrameNormalizationPlan.shouldNormalizeWebFrame {
            reasons.append(.webFrame)
        }
        if presentationApplicationPlan.shouldRefreshForReveal {
            reasons.append(.reveal)
        }
        if visibleSyncPlan.shouldAppendAnchorRefreshReason {
            reasons.append(.anchor)
        }
        return BrowserLifecycleExecutorHostedRefreshPlan(reasons: reasons)
    }

    static func visibleApplicationPlan(
        presentationApplicationPlan: BrowserLifecycleExecutorPresentationApplicationPlan,
        transientRecoveryPlan: BrowserLifecycleExecutorTransientRecoveryPlan?,
        transientRecoveryReason: BrowserLifecycleExecutorTransientRecoveryReason?,
        forcePresentationRefresh: Bool,
        hasPendingRefreshReasons: Bool,
        geometryStateShouldHideContainer: Bool,
        frameApplicationPlan: BrowserLifecycleExecutorFrameApplicationPlan,
        webFrameNormalizationPlan: BrowserLifecycleExecutorWebFrameNormalizationPlan
    ) -> BrowserLifecycleExecutorVisibleApplicationPlan {
        let visibleSyncPlan = visibleSyncPlan(
            presentationApplicationPlan: presentationApplicationPlan,
            transientRecoveryPlan: transientRecoveryPlan,
            transientRecoveryReason: transientRecoveryReason,
            forcePresentationRefresh: forcePresentationRefresh,
            hasPendingRefreshReasons: hasPendingRefreshReasons,
            geometryStateShouldHideContainer: geometryStateShouldHideContainer
        )
        let hostedRefreshPlan = hostedRefreshPlan(
            visibleSyncPlan: visibleSyncPlan,
            frameApplicationPlan: frameApplicationPlan,
            webFrameNormalizationPlan: webFrameNormalizationPlan,
            presentationApplicationPlan: presentationApplicationPlan
        )
        let effectiveTransientRecoveryPlan =
            visibleSyncPlan.shouldApplyTransientRecoveryPlan ? transientRecoveryPlan : nil
        let effectiveTransientRecoveryReason =
            visibleSyncPlan.shouldApplyTransientRecoveryPlan ? transientRecoveryReason : nil
        return BrowserLifecycleExecutorVisibleApplicationPlan(
            shouldPreserveVisibleOnTransientGeometry: visibleSyncPlan.shouldPreserveVisibleOnTransientGeometry,
            shouldApplyPresentationApplicationPlan: visibleSyncPlan.shouldApplyPresentationApplicationPlan,
            transientRecoveryPlan: effectiveTransientRecoveryPlan,
            transientRecoveryReason: effectiveTransientRecoveryReason,
            shouldTrackVisibleEntry: visibleSyncPlan.shouldTrackVisibleEntry,
            hostedRefreshPlan: hostedRefreshPlan
        )
    }

    private static func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance &&
            abs(lhs.origin.y - rhs.origin.y) <= tolerance &&
            abs(lhs.size.width - rhs.size.width) <= tolerance &&
            abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private static func frameExtendsOutsideBounds(_ frame: CGRect, bounds: CGRect) -> Bool {
        frame.minX < bounds.minX ||
            frame.minY < bounds.minY ||
            frame.maxX > bounds.maxX ||
            frame.maxY > bounds.maxY
    }
}
