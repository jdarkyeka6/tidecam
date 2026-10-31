import Foundation
import WatchConnectivity

/// A foreground-only camera control channel. Commands are sent only when
/// the paired watch is reachable. No queued shutter commands execute later.
@MainActor
final class WatchRemoteBridge: NSObject, ObservableObject, WCSessionDelegate {
    var commandHandler: ((String, Double?) -> (Bool, String))?
    var stateProvider: (() -> [String: Any])?
    private var latestSnapshot: [String: Any] = [:]

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publishState() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let state = stateProvider?() else { return }
        if NSDictionary(dictionary: state).isEqual(to: latestSnapshot) { return }
        latestSnapshot = state

        // Saved snapshot is useful if the watch reconnects later. Actions
        // themselves use only live messages and never get queued.
        try? WCSession.default.updateApplicationContext(state)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(
                ["type": "state", "state": state],
                replyHandler: nil,
                errorHandler: nil
            )
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.publishState() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.publishState() }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            guard let command = message["command"] as? String else {
                replyHandler(["ok": false, "message": "Unknown command"])
                return
            }
            let value = (message["value"] as? NSNumber)?.doubleValue
            let result = self.commandHandler?(command, value)
                ?? (false, "Open TideCam on your iPhone")
            replyHandler(["ok": result.0, "message": result.1])
            self.publishState()
        }
    }
}
