//
//  AppDelegate+Sync.swift
//  Luna
//
//  iCloud sync's app half (docs/plans/SYNC-PLAN.md §1, §4, S11): the entitlement
//  gate, and `AppSync`, which builds the coordinator over the main store and
//  hooks it to Settings, the session, the settings mirror and the History
//  menu. Private windows have stores of their own and never get one.
//

import AppKit
import BrowserKit
import Security

enum SyncGate {

    /// Whether this build may touch CloudKit. Constructing a `CKContainer`
    /// without the entitlement crashes, and only `make signed` carries it:
    /// Debug, the test host and CI do not.
    static var isEntitled: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let services = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        return (services as? [String])?.contains("CloudKit") == true
    }
}

@MainActor
final class AppSync {

    nonisolated static let containerIdentifier = "iCloud.dev.novapps.luna"

    /// What this Mac is called in the other Macs' History menus.
    static let deviceName = Host.current().localizedName ?? "Mac"

    /// Set once, in init, after the closures that reach back to `self` are made.
    private(set) var coordinator: SyncCoordinator!
    private let store: BrowserStore
    private let settings: SyncSettings
    private var observers: [Any] = []

    /// Nil without the entitlement, and Settings says why. Otherwise running,
    /// with an engine only if sync was left on.
    static func start(
        store: BrowserStore,
        session: BrowserSession?,
        settings: SyncSettings = .shared,
        entitled: Bool = SyncGate.isEntitled,
        makeEngine: @escaping @Sendable (SyncCoordinator, Data?) -> any SyncEngineControl = {
            SyncCloudKitEngine(containerIdentifier: containerIdentifier, state: $1, coordinator: $0)
        }
    ) async -> AppSync? {
        guard entitled else {
            settings.status = .needsSignedBuild
            return nil
        }
        let sync = AppSync(store: store, session: session, settings: settings, makeEngine: makeEngine)
        // The mirror first, so what changed while Luna was closed goes up with the rest.
        try? await SyncedDefaults.record(to: store)
        try? await sync.coordinator.start()
        await sync.refresh()
        await sync.activated()
        return sync
    }

    private init(
        store: BrowserStore,
        session: BrowserSession?,
        settings: SyncSettings,
        makeEngine: @escaping @Sendable (SyncCoordinator, Data?) -> any SyncEngineControl
    ) {
        self.store = store
        self.settings = settings
        coordinator = SyncCoordinator(
            store: store,
            makeEngine: makeEngine,
            // Through the session's write chain (S10), or straight to the store
            // once there is no session to overwrite it.
            applyInbound: { [weak session] changes, isFirstFetch in
                if let session {
                    try await session.applyRemote(changes, isFirstFetch: isFirstFetch)
                } else {
                    try await store.applyRemote(changes, isFirstFetch: isFirstFetch)
                }
            },
            applySettings: { changes in try await SyncedDefaults.apply(changes, store: store) },
            applyDevices: { [weak self] _ in await self?.refreshOtherMacs() },
            // A sign-out, an account switch or a removal on another Mac turns
            // zones off from inside the coordinator, so every status change
            // also re-reads them.
            onStatus: { [weak self] status in
                self?.settings.status = status
                Task { await self?.refresh() }
            }
        )
        hookUpSettings()
        let coordinator = coordinator!
        observers.append(SyncedDefaults.observe(store) { try? await coordinator.pushOutbox() })
        if let session {
            observers.append(session.addChangeObserver { [weak self] in self?.publishPresence() })
        }
    }

    /// App activation: the §4 quiet retry, other Macs' changes when push has
    /// not brought them, and this Mac's tabs for their menus.
    func activated() async {
        try? await coordinator.fetch()
        try? await coordinator.publishPresence(name: Self.deviceName)
    }

    private func publishPresence() {
        Task { [coordinator] in try? await coordinator?.publishPresence(name: Self.deviceName) }
    }

    private func hookUpSettings() {
        settings.setEnabled = { [weak self] on in
            self?.act { on ? try await $0.enable(zones: Set(SyncZone.switched)) : try await $0.disable() }
        }
        settings.setZone = { [weak self] zone, on in self?.act { try await $0.setZone(zone, enabled: on) } }
        settings.syncNow = { [weak self] in self?.act { try await $0.syncNow() } }
        settings.removeAll = { [weak self] in self?.act { try await $0.removeAll() } }
    }

    /// Runs one of the account page's actions, then writes the zones and the
    /// status back, whichever way it ended.
    private func act(_ action: @escaping @Sendable (SyncCoordinator) async throws -> Void) {
        Task { [coordinator] in
            guard let coordinator else { return }
            try? await action(coordinator)
            await refresh()
        }
    }

    private func refresh() async {
        settings.zones = (try? await store.enabledSyncZones()) ?? []
        settings.status = await coordinator.status
        await refreshOtherMacs()
    }

    private func refreshOtherMacs() async {
        MainMenu.setOtherMacs((try? await coordinator.otherMacs()) ?? [], in: NSApp)
    }
}
