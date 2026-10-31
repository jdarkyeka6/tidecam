import Foundation
import WatchConnectivity
import WatchKit

@MainActor
final class RemoteModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var connected = false
    @Published var phoneReady = false
    @Published var recording = false
    @Published var bursting = false
    @Published var busy = false
    @Published var burstCount = 0
    @Published var mode = "PHOTO"
    @Published var zoom = 1.0
    @Published var minZoom = 1.0
    @Published var maxZoom = 10.0
    @Published var feedback = "Open TideCam on iPhone"

    func start() {
        guard WCSession.isSupported() else {
            feedback = "WatchConnectivity unavailable"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        connected = session.activationState == .activated && session.isReachable
        if !session.receivedApplicationContext.isEmpty {
            update(session.receivedApplicationContext)
        }
    }

    private func update(_ state: [String: Any]) {
        if let value = state["ready"] as? Bool { phoneReady = value }
        if let value = state["recording"] as? Bool { recording = value }
        if let value = state["bursting"] as? Bool { bursting = value }
        if let value = state["busy"] as? Bool { busy = value }
        if let value = state["burstCount"] as? Int { burstCount = value }
        if let value = state["mode"] as? String { mode = value }
        if let value = state["zoom"] as? Double { zoom = value }
        if let value = state["minZoom"] as? Double { minZoom = value }
        if let value = state["maxZoom"] as? Double { maxZoom = value }
    }

    func command(_ name: String, value: Double? = nil) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        connected = session.activationState == .activated && session.isReachable
        guard connected else {
            feedback = "Open TideCam on your iPhone"
            WKInterfaceDevice.current().play(.failure)
            return
        }
        var request: [String: Any] = ["command": name]
        if let value { request["value"] = value }

        session.sendMessage(request, replyHandler: { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                let ok = response["ok"] as? Bool ?? false
                self.feedback = response["message"] as? String ??
                    (ok ? "Command sent" : "Camera unavailable")
                WKInterfaceDevice.current().play(ok ? .success : .failure)
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                self?.feedback = "Connection lost: \(error.localizedDescription)"
                self?.connected = false
                WKInterfaceDevice.current().play(.failure)
            }
        })
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.connected = activationState == .activated && session.isReachable
            self.feedback = self.connected ?
                "TideCam connected" : "Open TideCam on iPhone"
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.connected = session.activationState == .activated && session.isReachable
            self.feedback = self.connected ?
                "Connected" : "Open TideCam on iPhone"
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in self.update(applicationContext) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard message["type"] as? String == "state",
              let state = message["state"] as? [String: Any] else { return }
        Task { @MainActor in self.update(state) }
    }
}
