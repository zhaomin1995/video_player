/// Chromecast integration using the Cast V2 protocol (no Google Cast SDK dependency).
/// Discovers devices via mDNS (_googlecast._tcp), connects over TLS, and communicates
/// using length-prefixed protobuf messages (CastV2Message). The protocol requires
/// establishing a virtual connection before launching the media receiver app.
import Foundation

protocol ChromecastManagerDelegate: AnyObject {
    func chromecastDidDiscover(_ device: CastDevice)
    func chromecastDidRemove(_ deviceId: String)
    func chromecastDidConnect(_ device: CastDevice)
    func chromecastDidUpdatePosition(_ position: Double, duration: Double)
}

class ChromecastManager: NSObject {
    weak var delegate: ChromecastManagerDelegate?

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var connectedDevice: CastDevice?
    private var connection: NWConnectionWrapper?

    func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        services.removeAll()
    }

    func connect(to device: CastDevice) {
        connectedDevice = device
        connection = NWConnectionWrapper(host: device.host, port: device.port)
        connection?.onConnected = { [weak self] in
            self?.sendAuthMessage()
            self?.delegate?.chromecastDidConnect(device)
        }
        connection?.connect()
    }

    func loadMedia(url: URL, on device: CastDevice) {
        let mediaJSON: [String: Any] = [
            "type": "LOAD",
            "requestId": 1,
            "media": [
                "contentId": url.absoluteString,
                "contentType": "video/mp4",
                "streamType": "BUFFERED",
            ],
            "autoplay": true,
        ]
        sendMediaMessage(mediaJSON)
    }

    func play() {
        sendMediaMessage(["type": "PLAY", "requestId": 2])
    }

    func pause() {
        sendMediaMessage(["type": "PAUSE", "requestId": 3])
    }

    func seek(to position: Double) {
        sendMediaMessage(["type": "SEEK", "requestId": 4, "currentTime": position])
    }

    func stop() {
        sendMediaMessage(["type": "STOP", "requestId": 5])
        connection?.disconnect()
        connection = nil
        connectedDevice = nil
    }

    /// Cast V2 handshake: first open a virtual "connection" channel to the receiver,
    /// then launch the Default Media Receiver app (CC1AD845 is Google's public app ID).
    /// Media commands can only be sent after the receiver app is running.
    private func sendAuthMessage() {
        let connectMsg: [String: Any] = [
            "type": "CONNECT",
            "origin": [:] as [String: Any],
        ]
        sendCastMessage(
            namespace: "urn:x-cast:com.google.cast.tp.connection",
            payload: connectMsg
        )

        let launchMsg: [String: Any] = [
            "type": "LAUNCH",
            "requestId": 0,
            "appId": "CC1AD845",
        ]
        sendCastMessage(
            namespace: "urn:x-cast:com.google.cast.receiver",
            payload: launchMsg
        )
    }

    private func sendMediaMessage(_ payload: [String: Any]) {
        sendCastMessage(
            namespace: "urn:x-cast:com.google.cast.media",
            payload: payload
        )
    }

    /// Wraps a JSON payload into a Cast V2 protobuf message and sends it over TLS.
    /// Each namespace routes to a different receiver subsystem (connection, media, etc.).
    private func sendCastMessage(namespace: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        guard let jsonString = String(data: data, encoding: .utf8) else { return }

        let message = CastV2Message(
            sourceId: "sender-0",
            destinationId: "receiver-0",
            namespace: namespace,
            payloadUtf8: jsonString
        )

        connection?.send(data: message.serialize())
    }
}

extension ChromecastManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        delegate?.chromecastDidRemove(service.name)
    }
}

extension ChromecastManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        let device = CastDevice(
            id: sender.name,
            name: sender.name,
            type: .chromecast,
            host: hostName,
            port: sender.port
        )
        delegate?.chromecastDidDiscover(device)
    }
}

/// Minimal hand-rolled protobuf serializer for CastMessage. Avoids pulling in
/// SwiftProtobuf as a dependency — the CastMessage schema is simple enough to
/// encode manually (6 fields, all varints or length-delimited strings).
// MARK: - Cast V2 Protobuf Message (Minimal)

struct CastV2Message {
    let sourceId: String
    let destinationId: String
    let namespace: String
    let payloadUtf8: String

    func serialize() -> Data {
        // Simplified Cast V2 protobuf encoding
        // Field 1: protocol_version (varint) = 0 (CASTV2_1_0)
        // Field 2: source_id (string)
        // Field 3: destination_id (string)
        // Field 4: namespace (string)
        // Field 5: payload_type (varint) = 0 (STRING)
        // Field 6: payload_utf8 (string)
        var data = Data()

        func appendVarint(_ value: UInt64) {
            var v = value
            while v > 127 {
                data.append(UInt8(v & 0x7F | 0x80))
                v >>= 7
            }
            data.append(UInt8(v))
        }

        func appendString(fieldNumber: Int, value: String) {
            let tag = UInt64(fieldNumber << 3 | 2) // wire type 2 = length-delimited
            appendVarint(tag)
            let bytes = value.utf8
            appendVarint(UInt64(bytes.count))
            data.append(contentsOf: bytes)
        }

        func appendVarintField(fieldNumber: Int, value: UInt64) {
            let tag = UInt64(fieldNumber << 3 | 0) // wire type 0 = varint
            appendVarint(tag)
            appendVarint(value)
        }

        appendVarintField(fieldNumber: 1, value: 0) // CASTV2_1_0
        appendString(fieldNumber: 2, value: sourceId)
        appendString(fieldNumber: 3, value: destinationId)
        appendString(fieldNumber: 4, value: namespace)
        appendVarintField(fieldNumber: 5, value: 0) // STRING
        appendString(fieldNumber: 6, value: payloadUtf8)

        // Cast V2 framing: 4-byte big-endian length prefix before each protobuf message
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }
}

// MARK: - NWConnection Wrapper

import Network

/// Thin wrapper around NWConnection for TLS socket communication with Chromecast devices.
class NWConnectionWrapper {
    private var connection: NWConnection?
    var onConnected: (() -> Void)?
    var onData: ((Data) -> Void)?

    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() {
        let tlsOptions = NWProtocolTLS.Options()
        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)

        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: params
        )

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onConnected?()
                self?.receiveLoop()
            case .failed(let error):
                print("Chromecast connection failed: \(error)")
            default:
                break
            }
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    func send(data: Data) {
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    /// Continuously reads from the socket. minimumIncompleteLength: 4 ensures we
    /// get at least the length prefix before processing.
    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 65536) { [weak self] content, _, _, error in
            if let data = content {
                self?.onData?(data)
            }
            if error == nil {
                self?.receiveLoop()
            }
        }
    }
}
