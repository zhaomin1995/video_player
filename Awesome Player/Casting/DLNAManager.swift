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
        // controlURL is set by connect() asynchronously (fetches the device
        // description XML to find the AVTransport service path). If callers
        // call connect() then immediately loadMedia, the URLSession fetch
        // hasn't completed yet — chain here so loadMedia self-bootstraps.
        guard let controlURL = controlURL else {
            fetchDeviceDescription(device: device) { [weak self] ctrl in
                guard let self = self, let ctrl = ctrl else {
                    wlog(.dlna, "couldn't resolve controlURL for \(device.host)")
                    return
                }
                self.controlURL = ctrl
                self.connectedDevice = device
                self.delegate?.dlnaDidConnect(device)
                self.loadMedia(url: url, on: device)
            }
            return
        }
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

    private var ssdpSocket: Int32 = -1

    /// SSDP M-SEARCH via BSD sockets. NWConnection's UDP "connection" model
    /// doesn't deliver unicast responses to a multicast send — replies come
    /// from the device's own IP, not from the multicast group. Raw sockets
    /// don't have this constraint.
    private func sendSSDPSearch() {
        // Close any prior socket
        if ssdpSocket >= 0 { close(ssdpSocket); ssdpSocket = -1 }

        let sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            wlog(.dlna, "socket() failed")
            return
        }

        // Reuse + broadcast capability
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Receive timeout so the read loop can exit
        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Bind to ephemeral port (lets kernel pick)
        var local = sockaddr_in()
        local.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        local.sin_family = sa_family_t(AF_INET)
        local.sin_port = 0
        local.sin_addr.s_addr = INADDR_ANY.bigEndian
        let bindRet = withUnsafePointer(to: &local) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindRet < 0 { wlog(.dlna, "bind failed"); close(sock); return }

        // Multicast destination 239.255.255.250:1900
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &dest.sin_addr)

        let msg = "M-SEARCH * HTTP/1.1\r\n" +
                  "HOST: 239.255.255.250:1900\r\n" +
                  "MAN: \"ssdp:discover\"\r\n" +
                  "MX: 3\r\n" +
                  "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n"
        let data = msg.data(using: .utf8) ?? Data()
        let sent = data.withUnsafeBytes { buf -> Int in
            withUnsafePointer(to: &dest) { destPtr in
                destPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 { wlog(.dlna, "sendto failed"); close(sock); return }

        ssdpSocket = sock
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.receiveSSDPResponses(socket: sock)
        }
    }

    private func receiveSSDPResponses(socket sock: Int32) {
        let bufSize = 4096
        var buf = [UInt8](repeating: 0, count: bufSize)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            var src = sockaddr_in()
            var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &src) { srcPtr in
                srcPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(sock, &buf, bufSize, 0, sa, &srcLen)
                }
            }
            if n <= 0 { continue }
            let data = Data(bytes: buf, count: n)
            if let response = String(data: data, encoding: .utf8) {
                parseSSDPResponse(response)
            }
        }
        close(sock)
        if ssdpSocket == sock { ssdpSocket = -1 }
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
            port: port,
            descriptionURL: loc
        )

        DispatchQueue.main.async {
            self.delegate?.dlnaDidDiscover(device)
        }
    }

    // MARK: - UPnP

    private func fetchDeviceDescription(device: CastDevice, completion: @escaping (String?) -> Void) {
        // Use the LOCATION URL from the SSDP advertisement. Different vendors
        // use different paths (Samsung uses /dmr, others use /xml/...).
        // Fall back to a guessed path only if we somehow didn't capture LOCATION.
        let urlString = device.descriptionURL
            ?? "http://\(device.host):\(device.port)/xml/device_description.xml"
        guard let url = URL(string: urlString) else { completion(nil); return }
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

    /// Walk the `<service>` blocks looking for the AVTransport service —
    /// that's the one with SetAVTransportURI/Play. Devices typically also
    /// expose RenderingControl and ConnectionManager which appear first in
    /// the XML, so naively grabbing the first <controlURL> picks the wrong one.
    private func parseControlURL(from xml: String, baseHost: String, basePort: Int) -> String? {
        var remaining = xml[xml.startIndex...]
        while let svcOpen = remaining.range(of: "<service>"),
              let svcClose = remaining.range(of: "</service>", range: svcOpen.upperBound..<remaining.endIndex) {
            let serviceBlock = remaining[svcOpen.upperBound..<svcClose.lowerBound]
            if serviceBlock.contains("AVTransport"),
               let ctrlOpen = serviceBlock.range(of: "<controlURL>"),
               let ctrlClose = serviceBlock.range(of: "</controlURL>", range: ctrlOpen.upperBound..<serviceBlock.endIndex) {
                let path = String(serviceBlock[ctrlOpen.upperBound..<ctrlClose.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if path.hasPrefix("http") { return path }
                return "http://\(baseHost):\(basePort)\(path)"
            }
            remaining = remaining[svcClose.upperBound...]
        }
        return nil
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
