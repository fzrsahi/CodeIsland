import Combine
import Foundation
import MultipeerConnectivity
import os
import CodeIslandCore

@MainActor
final class AppleCompanionPublisher: NSObject, ObservableObject {
    static let shared = AppleCompanionPublisher()

    private static let serviceType = "codeisland"
    private static let log = Logger(subsystem: "com.codeisland", category: "apple-companion")

    @Published private(set) var enabled = false
    @Published private(set) var advertising = false
    @Published private(set) var connectedPeerNames: [String] = []
    @Published private(set) var lastError: String?

    var bluetoothPoweredOn: Bool { bluetooth.poweredOn }
    var bluetoothAdvertising: Bool { bluetooth.advertising }
    var bluetoothSubscribed: Bool { bluetooth.hasSubscribers }

    /// The phone names the session its card was showing. Passing it on keeps a
    /// tap acting on what the user actually saw rather than on whatever reached
    /// the head of the queue in the meantime (#308/#310, still live on this
    /// path). Nil only when an older companion build sends no session id.
    var onControlCommand: ((BuddyControlCommand, String?) -> Void)?
    var onFocusRequest: ((MascotID) -> Void)?
    var onQuestionAnswer: ((String, String?) -> Void)?

    private weak var appState: AppState?
    private let peerID: MCPeerID
    /// Created only while the companion is on. Touching them at launch (which
    /// `configure(enabled: false)` used to do, to stop and disconnect) spins up
    /// an MCSession and a service advertiser — and their background threads —
    /// for a feature that is off by default.
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var heartbeatTimer: Timer?
    private var sequence: UInt64 = 0
    private var lastSentContentKey: String?
    private let bluetooth = AppleCompanionBluetoothPeripheral()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private override init() {
        let hostName = Host.current().localizedName ?? "Mac"
        let displayName = "CodeIsland \(hostName)"
        self.peerID = MCPeerID(displayName: String(displayName.prefix(63)))
        super.init()
    }

    func attach(_ appState: AppState) {
        self.appState = appState
    }

    func configure(enabled: Bool, heartbeatSeconds: Double) {
        self.enabled = enabled
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        guard enabled else {
            stopMultipeer()
            bluetooth.configure(enabled: false)
            advertising = false
            connectedPeerNames = []
            return
        }

        lastError = nil
        startMultipeer()
        bluetooth.configure(enabled: true)
        advertising = true
        let heartbeat = max(1.0, heartbeatSeconds)
        let timer = Timer.scheduledTimer(withTimeInterval: heartbeat, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush(reason: "heartbeat")
            }
        }
        // The iPhone watchdog allows 8–24 s, so a late beat costs nothing.
        timer.tolerance = heartbeat * 0.1
        heartbeatTimer = timer
        flush(reason: "enabled")
    }

    func notifyDirty() {
        flush(reason: "change")
    }

    func reconnect() {
        guard enabled else { return }
        stopMultipeer()
        connectedPeerNames = []
        startMultipeer()
        advertising = true
        bluetooth.configure(enabled: true)
        flush(reason: "reconnect")
    }

    /// Build the Multipeer objects the first time the companion is switched on.
    private func startMultipeer() {
        if session == nil {
            let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
            session.delegate = self
            self.session = session
        }
        if advertiser == nil {
            let advertiser = MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: ["protocol": "1"],
                serviceType: Self.serviceType
            )
            advertiser.delegate = self
            self.advertiser = advertiser
        }
        advertiser?.startAdvertisingPeer()
    }

    /// Tear them down and let them go. Does nothing when they were never built,
    /// so switching the companion off costs nothing.
    private func stopMultipeer() {
        advertiser?.stopAdvertisingPeer()
        session?.disconnect()
        advertiser = nil
        session = nil
    }

    private func flush(reason: String) {
        PerfCounters.shared?.bump(.publishCompanion)
        guard enabled, let appState else { return }
        sequence &+= 1
        let payload = appState.appleCompanionStatePayload(sequence: sequence)

        if reason == "change" {
            let key = PublishDedupe.companionContentKey(for: payload)
            guard key != lastSentContentKey else { return }
            lastSentContentKey = key
        } else {
            lastSentContentKey = PublishDedupe.companionContentKey(for: payload)
        }

        bluetooth.publish(payload)

        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            let data = try encoder.encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            Self.log.debug("push(\(reason)): seq=\(payload.sequence) source=\(payload.source) status=\(payload.status.rawValue) peers=\(session.connectedPeers.count)")
        } catch {
            lastError = error.localizedDescription
            Self.log.error("push failed: \(error.localizedDescription)")
        }
    }

    /// Internal so tests can check which commands are taken.
    func handleCommand(_ command: AppleCompanionCommandPayload) {
        guard !command.type.decidesForTheUser else {
            Self.log.notice("ignored \(command.type.rawValue, privacy: .public): iPhone Buddy can't answer requests until it pairs with this Mac")
            return
        }
        switch command.type {
        case .requestCurrentState:
            flush(reason: "requested")
        case .approveCurrentPermission:
            onControlCommand?(.approveCurrentPermission, command.sessionId)
        case .denyCurrentPermission:
            onControlCommand?(.denyCurrentPermission, command.sessionId)
        case .skipCurrentQuestion:
            onControlCommand?(.skipCurrentQuestion, command.sessionId)
        case .answerQuestion:
            if let answer = command.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
               !answer.isEmpty {
                onQuestionAnswer?(answer, command.sessionId)
            }
        case .focus:
            onFocusRequest?(MascotID(sourceName: command.source) ?? .claude)
        }
    }

    private func refreshConnectedPeers() {
        connectedPeerNames = (session?.connectedPeers ?? []).map(\.displayName).sorted()
    }
}

extension AppleCompanionPublisher: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            guard self.enabled else {
                invitationHandler(false, nil)
                return
            }
            guard let session = self.session else {
                invitationHandler(false, nil)
                return
            }
            Self.log.info("accepted invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.advertising = false
            self.lastError = error.localizedDescription
            Self.log.error("advertising failed: \(error.localizedDescription)")
        }
    }
}

extension AppleCompanionPublisher: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.refreshConnectedPeers()
            if state == .connected {
                self.flush(reason: "peer-connected")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let command = try self.decoder.decode(AppleCompanionCommandPayload.self, from: data)
                self.handleCommand(command)
            } catch {
                self.lastError = "Ignored command from \(peerID.displayName): \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
