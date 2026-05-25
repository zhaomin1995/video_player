import Foundation
import Network

protocol DLNAManagerDelegate: AnyObject {
    func dlnaDidDiscover(_ device: CastDevice)
    func dlnaDidRemove(_ deviceId: String)
    func dlnaDidConnect(_ device: CastDevice)
    func dlnaDidUpdatePosition(_ position: Double, duration: Double)
}

class DLNAManager {
    weak var delegate: DLNAManagerDelegate?

    private var ssdpConnection: NWConnection?
    private var connectedDevice: CastDevice?
    private var controlURL: String? = nil
    private var positionTimer: Timer?

    func startDiscovery() {
        sendSSDPSearch()
    }

    func stopDiscovery() {
        ssdpConnection?.cancel()
        ssdpConnection = nil
    }

    func connect(to device: CastDevice) {
        connectedDevice = device
        fetchDeviceDescription(device: device) { [weak self] url in
            self?.controlURL = url
            self?.delegate?.dlnaDidConnect(device)
        }
    }

    func loadMedia(url: URL, on device: CastDevice) {
        guard let controlURL = controlURL else { return }
        let soapAction = "SetAVTransportURI"
        let soapBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(url.absoluteString)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: soapAction, body: soapBody) { [weak self] _ in
            self?.play()
            self?.startPositionPolling()
        }
    }

    func play() {
        guard let controlURL = controlURL else { return }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Speed>1</Speed>
            </u:Play>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: "Play", body: body, completion: nil)
    }

    func pause() {
        guard let controlURL = controlURL else { return }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Pause>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: "Pause", body: body, completion: nil)
    }

    func seek(to position: Double) {
        guard let controlURL = controlURL else { return }
        let hours = Int(position) / 3600
        let minutes = (Int(position) % 3600) / 60
        let seconds = Int(position) % 60
        let target = String(format: "%02d:%02d:%02d", hours, minutes, seconds)

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <Unit>REL_TIME</Unit>
              <Target>\(target)</Target>
            </u:Seek>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: "Seek", body: body, completion: nil)
    }

    func stop() {
        positionTimer?.invalidate()
        positionTimer = nil

        guard let controlURL = controlURL else { return }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Stop>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: "Stop", body: body, completion: nil)
        connectedDevice = nil
        self.controlURL = nil
    }

    // MARK: - SSDP Discovery

    private func sendSSDPSearch() {
        let searchMessage = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
        \r

        """

        let group = NWEndpoint.Host("239.255.255.250")
        let port = NWEndpoint.Port(integerLiteral: 1900)

        let params = NWParameters.udp
        let connection = NWConnection(host: group, port: port, using: params)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                let data = searchMessage.data(using: .utf8)!
                connection.send(content: data, completion: .contentProcessed { _ in })

                self?.receiveSSDP(connection: connection)
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        ssdpConnection = connection

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            connection.cancel()
        }
    }

    private func receiveSSDP(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, error in
            if let data = content, let response = String(data: data, encoding: .utf8) {
                self?.parseSSDPResponse(response)
            }
            if error == nil {
                self?.receiveSSDP(connection: connection)
            }
        }
    }

    private func parseSSDPResponse(_ response: String) {
        guard response.contains("MediaRenderer") || response.contains("200 OK") else { return }

        var location: String?
        for line in response.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("location:") {
                location = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }

        guard let loc = location, let url = URL(string: loc) else { return }

        let host = url.host ?? ""
        let port = url.port ?? 80

        let device = CastDevice(
            id: "dlna-\(host):\(port)",
            name: "DLNA Renderer (\(host))",
            type: .dlna,
            host: host,
            port: port
        )

        DispatchQueue.main.async {
            self.delegate?.dlnaDidDiscover(device)
        }
    }

    // MARK: - UPnP

    private func fetchDeviceDescription(device: CastDevice, completion: @escaping (String?) -> Void) {
        let url = URL(string: "http://\(device.host):\(device.port)/xml/device_description.xml")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            let controlURL = self.parseControlURL(from: xml, baseHost: device.host, basePort: device.port)
            DispatchQueue.main.async {
                completion(controlURL)
            }
        }.resume()
    }

    private func parseControlURL(from xml: String, baseHost: String, basePort: Int) -> String? {
        if let range = xml.range(of: "<controlURL>") {
            let after = xml[range.upperBound...]
            if let endRange = after.range(of: "</controlURL>") {
                let path = String(after[..<endRange.lowerBound])
                return "http://\(baseHost):\(basePort)\(path)"
            }
        }
        return "http://\(baseHost):\(basePort)/MediaRenderer/AVTransport/Control"
    }

    private func sendSOAPAction(controlURL: String, action: String, body: String, completion: ((Data?) -> Void)?) {
        guard let url = URL(string: controlURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                completion?(data)
            }
        }.resume()
    }

    private func startPositionPolling() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.queryPosition()
        }
    }

    private func queryPosition() {
        guard let controlURL = controlURL else { return }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:GetPositionInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:GetPositionInfo>
          </s:Body>
        </s:Envelope>
        """
        sendSOAPAction(controlURL: controlURL, action: "GetPositionInfo", body: body) { [weak self] data in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else { return }
            let position = self?.parseTime(from: xml, tag: "RelTime") ?? 0
            let duration = self?.parseTime(from: xml, tag: "TrackDuration") ?? 0
            self?.delegate?.dlnaDidUpdatePosition(position, duration: duration)
        }
    }

    private func parseTime(from xml: String, tag: String) -> Double? {
        guard let range = xml.range(of: "<\(tag)>") else { return nil }
        let after = xml[range.upperBound...]
        guard let endRange = after.range(of: "</\(tag)>") else { return nil }
        let timeStr = String(after[..<endRange.lowerBound])
        let parts = timeStr.components(separatedBy: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}
