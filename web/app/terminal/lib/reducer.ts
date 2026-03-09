import {
  type AppState,
  type Workspace,
  type PaneGroup,
  type GroupTab,
  type Notification,
  createPaneGroup,
  createWorkspace,
  splitLeaf,
  removeLeaf,
  updateRatio,
  equalize,
  getLeaves,
  getAdjacentLeaf,
  getSpatialNeighbor,
  genId,
  nextTerminalTitle,
  createLeaf,
  insertTreeAt,
} from "./split-tree"

export type DropDirection = "left" | "right" | "up" | "down"

export type Action =
  // Workspace-level (sidebar)
  | { type: "ADD_WORKSPACE" }
  | { type: "CLOSE_WORKSPACE"; workspaceId: string }
  | { type: "SELECT_WORKSPACE"; workspaceId: string }
  | { type: "NEXT_WORKSPACE" }
  | { type: "PREV_WORKSPACE" }
  | { type: "UPDATE_WORKSPACE_TITLE"; workspaceId: string; title: string }
  // Per-pane tab actions (within active workspace)
  | { type: "ADD_TAB"; groupId: string }
  | { type: "CLOSE_TAB"; groupId: string; tabId: string }
  | { type: "SELECT_TAB"; groupId: string; tabId: string }
  | { type: "NEXT_TAB"; groupId: string }
  | { type: "PREV_TAB"; groupId: string }
  | { type: "REORDER_TAB"; groupId: string; tabId: string; toIndex: number }
  | { type: "DRAG_TAB_TO_GROUP"; fromGroupId: string; tabId: string; toGroupId: string; toIndex: number }
  | { type: "DRAG_TAB_TO_PANE"; fromGroupId: string; tabId: string; targetGroupId: string; direction: DropDirection }
  // Pane-level (within active workspace)
  | { type: "SPLIT_PANE"; groupId: string; direction: DropDirection }
  | { type: "CLOSE_PANE"; groupId: string }
  | { type: "RESIZE_SPLIT"; splitId: string; ratio: number }
  | { type: "FOCUS_GROUP"; groupId: string }
  | { type: "EQUALIZE_SPLITS" }
  | { type: "FOCUS_NEXT_GROUP" }
  | { type: "FOCUS_PREV_GROUP" }
  | { type: "FOCUS_DIRECTION"; dir: "left" | "right" | "up" | "down" }
  // Title updates from OSC (searches all workspaces)
  | { type: "UPDATE_TAB_TITLE"; tabId: string; title: string }
  // Metadata updates from session_metadata (searches all workspaces)
  | { type: "UPDATE_TAB_METADATA"; tabId: string; metadata: {
      title?: string; description?: string; cwd?: string; dir?: string
      branch?: string; isDirty?: boolean; ports?: number[]
    }}
  // Notification actions
  | { type: "SET_NOTIFICATIONS"; notifications: Notification[] }
  | { type: "ADD_NOTIFICATION"; notification: Notification }
  | { type: "MARK_NOTIFICATION_READ"; notificationId: number }
  | { type: "CLEAR_NOTIFICATIONS"; sessionId?: number }

export function createInitialState(): AppState {
  const ws = createWorkspace()
  return {
    workspaces: { [ws.id]: ws },
    workspaceOrder: [ws.id],
    activeWorkspaceId: ws.id,
    notifications: [],
  }
}

/** Helper: get the active workspace */
function activeWs(state: AppState): Workspace {
  return state.workspaces[state.activeWorkspaceId]
}

/** Helper: update the active workspace immutably */
function updateActiveWs(state: AppState, patch: Partial<Workspace>): AppState {
  const ws = activeWs(state)
  return {
    ...state,
    workspaces: {
      ...state.workspaces,
      [ws.id]: { ...ws, ...patch },
    },
  }
}

/** Helper: remove a pane group from a workspace, returning updated workspace or null */
function removeGroupFromWs(ws: Workspace, groupId: string): Workspace | null {
  const leaves = getLeaves(ws.root)
  if (leaves.length <= 1) return null

  const newRoot = removeLeaf(ws.root, groupId)
  if (!newRoot) return null

  const { [groupId]: _removed, ...remainingGroups } = ws.groups

  let newFocus = ws.focusedGroupId
  if (newFocus === groupId) {
    const adj = getAdjacentLeaf(ws.root, groupId, "prev")
    const newLeaves = getLeaves(newRoot)
    newFocus = adj && newLeaves.includes(adj) ? adj : newLeaves[0]
  }

  return { ...ws, root: newRoot, groups: remainingGroups, focusedGroupId: newFocus }
}

/** Get the focused pane's active tab title for workspace display */
function getWorkspaceTitle(ws: Workspace): string {
  const group = ws.groups[ws.focusedGroupId]
  if (!group) return ws.title
  const tab = group.tabs.find((t) => t.id === group.activeTabId)
  return tab?.title ?? ws.title
}

/** Build a subtitle string from the focused tab's metadata */
function getWorkspaceSubtitle(ws: Workspace): string | undefined {
  const group = ws.groups[ws.focusedGroupId]
  if (!group) return undefined
  const tab = group.tabs.find((t) => t.id === group.activeTabId)
  if (!tab) return undefined
  if (tab.description) return tab.description
  const parts: string[] = []
  if (tab.branch) parts.push(tab.branch + (tab.isDirty ? "*" : ""))
  if (tab.dir) parts.push(tab.dir)
  return parts.length > 0 ? parts.join(" \u00b7 ") : undefined
}

export function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    // --- Workspace-level actions ---

    case "ADD_WORKSPACE": {
      const ws = createWorkspace()
      return {
        ...state,
        workspaces: { ...state.workspaces, [ws.id]: ws },
        workspaceOrder: [...state.workspaceOrder, ws.id],
        activeWorkspaceId: ws.id,
      }
    }

    case "CLOSE_WORKSPACE": {
      if (state.workspaceOrder.length <= 1) return state
      const idx = state.workspaceOrder.indexOf(action.workspaceId)
      if (idx === -1) return state
      const newOrder = state.workspaceOrder.filter((id) => id !== action.workspaceId)
      const { [action.workspaceId]: _removed, ...remaining } = state.workspaces
      let newActive = state.activeWorkspaceId
      if (newActive === action.workspaceId) {
        newActive = newOrder[Math.min(idx, newOrder.length - 1)]
      }
      return {
        ...state,
        workspaces: remaining,
        workspaceOrder: newOrder,
        activeWorkspaceId: newActive,
      }
    }

    case "SELECT_WORKSPACE": {
      if (state.activeWorkspaceId === action.workspaceId) return state
      if (!state.workspaces[action.workspaceId]) return state
      return { ...state, activeWorkspaceId: action.workspaceId }
    }

    case "NEXT_WORKSPACE": {
      const idx = state.workspaceOrder.indexOf(state.activeWorkspaceId)
      if (idx === -1 || state.workspaceOrder.length <= 1) return state
      const nextIdx = (idx + 1) % state.workspaceOrder.length
      return { ...state, activeWorkspaceId: state.workspaceOrder[nextIdx] }
    }

    case "PREV_WORKSPACE": {
      const idx = state.workspaceOrder.indexOf(state.activeWorkspaceId)
      if (idx === -1 || state.workspaceOrder.length <= 1) return state
      const prevIdx = (idx - 1 + state.workspaceOrder.length) % state.workspaceOrder.length
      return { ...state, activeWorkspaceId: state.workspaceOrder[prevIdx] }
    }

    case "UPDATE_WORKSPACE_TITLE": {
      const ws = state.workspaces[action.workspaceId]
      if (!ws || ws.title === action.title) return state
      return {
        ...state,
        workspaces: {
          ...state.workspaces,
          [action.workspaceId]: { ...ws, title: action.title },
        },
      }
    }

    // --- Per-pane tab actions ---

    case "ADD_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group) return state
      const tabId = genId()
      const newTab: GroupTab = { id: tabId, title: nextTerminalTitle(), type: "terminal" }
      const newGroup = { ...group, tabs: [...group.tabs, newTab], activeTabId: tabId }
      return updateActiveWs(state, {
        groups: { ...ws.groups, [group.id]: newGroup },
      })
    }

    case "CLOSE_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group) return state
      if (group.tabs.length <= 1) {
        // Last tab — close the pane
        return reducer(state, { type: "CLOSE_PANE", groupId: action.groupId })
      }
      const idx = group.tabs.findIndex((t) => t.id === action.tabId)
      if (idx === -1) return state
      const newTabs = group.tabs.filter((t) => t.id !== action.tabId)
      let newActive = group.activeTabId
      if (newActive === action.tabId) {
        newActive = newTabs[Math.min(idx, newTabs.length - 1)].id
      }
      return updateActiveWs(state, {
        groups: { ...ws.groups, [group.id]: { ...group, tabs: newTabs, activeTabId: newActive } },
      })
    }

    case "SELECT_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group || group.activeTabId === action.tabId) return state
      const updatedGroups = { ...ws.groups, [group.id]: { ...group, activeTabId: action.tabId } }
      const updatedWs = { ...ws, groups: updatedGroups, focusedGroupId: action.groupId }
      const tab = group.tabs.find((t) => t.id === action.tabId)
      if (tab && action.groupId === ws.focusedGroupId) {
        updatedWs.title = tab.title
        updatedWs.subtitle = getWorkspaceSubtitle(updatedWs)
      }
      return {
        ...state,
        workspaces: { ...state.workspaces, [ws.id]: updatedWs },
      }
    }

    case "NEXT_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group || group.tabs.length <= 1) return state
      const idx = group.tabs.findIndex((t) => t.id === group.activeTabId)
      const nextIdx = (idx + 1) % group.tabs.length
      return updateActiveWs(state, {
        groups: { ...ws.groups, [group.id]: { ...group, activeTabId: group.tabs[nextIdx].id } },
      })
    }

    case "PREV_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group || group.tabs.length <= 1) return state
      const idx = group.tabs.findIndex((t) => t.id === group.activeTabId)
      const prevIdx = (idx - 1 + group.tabs.length) % group.tabs.length
      return updateActiveWs(state, {
        groups: { ...ws.groups, [group.id]: { ...group, activeTabId: group.tabs[prevIdx].id } },
      })
    }

    case "REORDER_TAB": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group) return state
      const tabIdx = group.tabs.findIndex((t) => t.id === action.tabId)
      if (tabIdx === -1 || tabIdx === action.toIndex) return state
      const newTabs = [...group.tabs]
      const [moved] = newTabs.splice(tabIdx, 1)
      newTabs.splice(action.toIndex, 0, moved)
      return updateActiveWs(state, {
        groups: { ...ws.groups, [group.id]: { ...group, tabs: newTabs } },
      })
    }

    case "DRAG_TAB_TO_GROUP": {
      const ws = activeWs(state)
      const fromGroup = ws.groups[action.fromGroupId]
      const toGroup = ws.groups[action.toGroupId]
      if (!fromGroup || !toGroup) return state
      const tab = fromGroup.tabs.find((t) => t.id === action.tabId)
      if (!tab) return state

      // If same group, just reorder
      if (action.fromGroupId === action.toGroupId) {
        return reducer(state, { type: "REORDER_TAB", groupId: action.fromGroupId, tabId: action.tabId, toIndex: action.toIndex })
      }

      // Remove from source
      const fromTabs = fromGroup.tabs.filter((t) => t.id !== action.tabId)
      let groups = { ...ws.groups }
      let newRoot = ws.root

      if (fromTabs.length === 0) {
        // Source group is now empty — remove the pane
        const result = removeLeaf(ws.root, action.fromGroupId)
        if (!result) return state
        newRoot = result
        const { [action.fromGroupId]: _, ...rest } = groups
        groups = rest
      } else {
        let newActive = fromGroup.activeTabId
        if (newActive === action.tabId) {
          const oldIdx = fromGroup.tabs.findIndex((t) => t.id === action.tabId)
          newActive = fromTabs[Math.min(oldIdx, fromTabs.length - 1)].id
        }
        groups[action.fromGroupId] = { ...fromGroup, tabs: fromTabs, activeTabId: newActive }
      }

      // Insert into destination
      const toTabs = [...toGroup.tabs]
      toTabs.splice(action.toIndex, 0, tab)
      groups[action.toGroupId] = { ...toGroup, tabs: toTabs, activeTabId: tab.id }

      return updateActiveWs(state, {
        root: newRoot,
        groups,
        focusedGroupId: action.toGroupId,
      })
    }

    case "DRAG_TAB_TO_PANE": {
      const ws = activeWs(state)
      const fromGroup = ws.groups[action.fromGroupId]
      const targetGroup = ws.groups[action.targetGroupId]
      if (!fromGroup || !targetGroup) return state
      const tab = fromGroup.tabs.find((t) => t.id === action.tabId)
      if (!tab) return state

      // Create new pane group with the dragged tab
      const newGroupId = genId()
      const newGroup: PaneGroup = { id: newGroupId, tabs: [tab], activeTabId: tab.id }
      const newLeaf = createLeaf(newGroupId)

      // Insert new leaf adjacent to the target
      const dir = action.direction === "left" || action.direction === "right" ? "horizontal" : "vertical"
      const after = action.direction === "right" || action.direction === "down"
      const newRoot = insertTreeAt(ws.root, action.targetGroupId, newLeaf, dir, after)
      if (!newRoot) return state

      let groups = { ...ws.groups, [newGroupId]: newGroup }

      // Remove tab from source
      const fromTabs = fromGroup.tabs.filter((t) => t.id !== action.tabId)
      if (fromTabs.length === 0) {
        // Source pane is empty — remove it
        const cleaned = removeLeaf(newRoot, action.fromGroupId)
        if (!cleaned) return state
        const { [action.fromGroupId]: _, ...rest } = groups
        groups = rest
        return updateActiveWs(state, { root: cleaned, groups, focusedGroupId: newGroupId })
      } else {
        let newActive = fromGroup.activeTabId
        if (newActive === action.tabId) {
          const oldIdx = fromGroup.tabs.findIndex((t) => t.id === action.tabId)
          newActive = fromTabs[Math.min(oldIdx, fromTabs.length - 1)].id
        }
        groups[action.fromGroupId] = { ...fromGroup, tabs: fromTabs, activeTabId: newActive }
      }

      return updateActiveWs(state, { root: newRoot, groups, focusedGroupId: newGroupId })
    }

    // --- Pane-level actions (within active workspace) ---

    case "SPLIT_PANE": {
      const ws = activeWs(state)
      const group = ws.groups[action.groupId]
      if (!group) return state
      const dir = action.direction === "left" || action.direction === "right" ? "horizontal" : "vertical"
      const after = action.direction === "right" || action.direction === "down"
      const newGroup = createPaneGroup()
      const newRoot = splitLeaf(ws.root, action.groupId, dir, after, newGroup.id)
      if (!newRoot) return state
      return updateActiveWs(state, {
        root: newRoot,
        groups: { ...ws.groups, [newGroup.id]: newGroup },
        focusedGroupId: newGroup.id,
      })
    }

    case "CLOSE_PANE": {
      const ws = activeWs(state)
      const leaves = getLeaves(ws.root)
      if (leaves.length <= 1) {
        // Last pane in workspace — close the workspace
        return reducer(state, { type: "CLOSE_WORKSPACE", workspaceId: ws.id })
      }
      const updated = removeGroupFromWs(ws, action.groupId)
      if (!updated) return state
      return {
        ...state,
        workspaces: { ...state.workspaces, [ws.id]: updated },
      }
    }

    case "RESIZE_SPLIT": {
      const ws = activeWs(state)
      const newRoot = updateRatio(ws.root, action.splitId, action.ratio)
      if (newRoot === ws.root) return state
      return updateActiveWs(state, { root: newRoot })
    }

    case "FOCUS_GROUP": {
      const ws = activeWs(state)
      if (ws.focusedGroupId === action.groupId) return state
      if (!ws.groups[action.groupId]) return state
      const updated = { ...ws, focusedGroupId: action.groupId }
      updated.title = getWorkspaceTitle(updated)
      updated.subtitle = getWorkspaceSubtitle(updated)
      return {
        ...state,
        workspaces: { ...state.workspaces, [ws.id]: updated },
      }
    }

    case "EQUALIZE_SPLITS": {
      const ws = activeWs(state)
      return updateActiveWs(state, { root: equalize(ws.root) })
    }

    case "FOCUS_NEXT_GROUP": {
      const ws = activeWs(state)
      const next = getAdjacentLeaf(ws.root, ws.focusedGroupId, "next")
      if (!next || next === ws.focusedGroupId) return state
      const updated = { ...ws, focusedGroupId: next }
      updated.title = getWorkspaceTitle(updated)
      updated.subtitle = getWorkspaceSubtitle(updated)
      return { ...state, workspaces: { ...state.workspaces, [ws.id]: updated } }
    }

    case "FOCUS_PREV_GROUP": {
      const ws = activeWs(state)
      const prev = getAdjacentLeaf(ws.root, ws.focusedGroupId, "prev")
      if (!prev || prev === ws.focusedGroupId) return state
      const updated = { ...ws, focusedGroupId: prev }
      updated.title = getWorkspaceTitle(updated)
      updated.subtitle = getWorkspaceSubtitle(updated)
      return { ...state, workspaces: { ...state.workspaces, [ws.id]: updated } }
    }

    case "FOCUS_DIRECTION": {
      const ws = activeWs(state)
      const neighbor = getSpatialNeighbor(ws.root, ws.focusedGroupId, action.dir)
      if (!neighbor || neighbor === ws.focusedGroupId) return state
      const updated = { ...ws, focusedGroupId: neighbor }
      updated.title = getWorkspaceTitle(updated)
      updated.subtitle = getWorkspaceSubtitle(updated)
      return { ...state, workspaces: { ...state.workspaces, [ws.id]: updated } }
    }

    // --- Title updates (search all workspaces) ---

    case "UPDATE_TAB_TITLE": {
      for (const [wsId, ws] of Object.entries(state.workspaces)) {
        for (const [gid, group] of Object.entries(ws.groups)) {
          const idx = group.tabs.findIndex((t) => t.id === action.tabId)
          if (idx !== -1) {
            const tab = group.tabs[idx]
            if (tab.title === action.title) return state
            const newTabs = [...group.tabs]
            newTabs[idx] = { ...tab, title: action.title }
            const updatedWs = {
              ...ws,
              groups: { ...ws.groups, [gid]: { ...group, tabs: newTabs } },
            }
            // Update workspace title/subtitle if this is the focused pane's active tab
            if (gid === ws.focusedGroupId && group.activeTabId === action.tabId) {
              updatedWs.title = action.title
              updatedWs.subtitle = getWorkspaceSubtitle(updatedWs)
            }
            return {
              ...state,
              workspaces: { ...state.workspaces, [wsId]: updatedWs },
            }
          }
        }
      }
      return state
    }

    case "UPDATE_TAB_METADATA": {
      const meta = action.metadata
      for (const [wsId, ws] of Object.entries(state.workspaces)) {
        for (const [gid, group] of Object.entries(ws.groups)) {
          const idx = group.tabs.findIndex((t) => t.id === action.tabId)
          if (idx !== -1) {
            const tab = group.tabs[idx]
            const newTab = { ...tab }
            if (meta.title !== undefined) newTab.title = meta.title
            if (meta.description !== undefined) newTab.description = meta.description || undefined
            if (meta.cwd !== undefined) newTab.cwd = meta.cwd || undefined
            if (meta.dir !== undefined) newTab.dir = meta.dir || undefined
            if (meta.branch !== undefined) newTab.branch = meta.branch || undefined
            if (meta.isDirty !== undefined) newTab.isDirty = meta.isDirty
            if (meta.ports !== undefined) newTab.ports = meta.ports.length > 0 ? meta.ports : undefined
            const newTabs = [...group.tabs]
            newTabs[idx] = newTab
            const updatedWs = {
              ...ws,
              groups: { ...ws.groups, [gid]: { ...group, tabs: newTabs } },
            }
            // Update workspace title/subtitle if this is the focused pane's active tab
            if (gid === ws.focusedGroupId && group.activeTabId === action.tabId) {
              updatedWs.title = newTab.title
              updatedWs.subtitle = getWorkspaceSubtitle(updatedWs)
            }
            return {
              ...state,
              workspaces: { ...state.workspaces, [wsId]: updatedWs },
            }
          }
        }
      }
      return state
    }

    // --- Notification actions ---

    case "SET_NOTIFICATIONS": {
      // Merge: keep any notifications already added individually that aren't
      // in the server's list (handles race where notification broadcast arrives
      // before notifications_list during connection setup).
      const listIds = new Set(action.notifications.map((n: Notification) => n.id))
      const extra = state.notifications.filter((n) => !listIds.has(n.id))
      return { ...state, notifications: [...action.notifications, ...extra] }
    }

    case "ADD_NOTIFICATION":
      return { ...state, notifications: [...state.notifications, action.notification] }

    case "MARK_NOTIFICATION_READ":
      return {
        ...state,
        notifications: state.notifications.map((n) =>
          n.id === action.notificationId ? { ...n, isRead: true } : n
        ),
      }

    case "CLEAR_NOTIFICATIONS":
      return {
        ...state,
        notifications: action.sessionId != null
          ? state.notifications.filter((n) => n.sessionId !== action.sessionId)
          : [],
      }

    default:
      return state
  }
}
