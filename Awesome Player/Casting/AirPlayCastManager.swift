import Foundation

protocol AirPlayCastManagerDelegate: AnyObject {
    func airplayCastDidDiscover(_ device: CastDevice)
    func airplayCastDidRemove(_ deviceId: String)
    func airplayCastDidConnect(_ device: CastDevice)
    func airplayCastDidStartPlaying()
    func airplayCastDidFail(_ message: String)
}

class AirPlayCastManager: NSObject {
    weak var delegate: AirPlayCastManagerDelegate?

    private var browser: NetServiceBrowser?
    private var pendingServices: [NetService] = []
    private(set) var devices: [CastDevice] = []
    private var targetDevice: CastDevice?
    private var dlnaControlURL: String?

    func startDiscovery() {
        devices.removeAll()
        pendingServices.removeAll()
        browser?.stop()
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        pendingServices.removeAll()
    }

    func cast(fileURL: URL, httpServer: CastingHTTPServer, to device: CastDevice) {
        targetDevice = device
        dlnaControlURL = nil
        delegate?.airplayCastDidConnect(device)

        castLog("[AirPlay] Starting cast to \(device.name) (\(device.host))")
        httpServer.start(servingFile: fileURL) { [weak self] serverURL in
            guard let self = self, let url = serverURL else {
                self?.delegate?.airplayCastDidFail("HTTP server failed to start")
                return
            }
            castLog("[AirPlay] HTTP server ready: \(url.absoluteString)")
            self.castViaDLNA(host: device.host, mediaURL: url)
        }
    }

    func stop() {
        if let url = dlnaControlURL {
            sendDLNAAction(controlURL: url, action: "Stop", body: dlnaStopBody)
        }
        targetDevice = nil
        dlnaControlURL = nil
    }

    func seek(to position: Double) {
        guard let url = dlnaControlURL else { return }
        let h = Int(position) / 3600
        let m = (Int(position) % 3600) / 60
        let s = Int(position) % 60
        let target = String(format: "%02d:%02d:%02d", h, m, s)
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
        sendDLNAAction(controlURL: url, action: "Seek", body: body)
    }

    func pause() {
        guard let url = dlnaControlURL else { return }
        sendDLNAAction(controlURL: url, action: "Pause", body: dlnaPauseBody)
    }

    func play() {
        guard let url = dlnaControlURL else { return }
        sendDLNAAction(controlURL: url, action: "Play", body: dlnaPlayBody)
    }

    // MARK: - DLNA Cast

    private func castViaDLNA(host: String, mediaURL: URL) {
        let probeURLs = [
            "http://\(host):9197/dmr.xml",
            "http://\(host):9197/rootDesc.xml",
            "http://\(host):8080/description.xml",
            "http://\(host):49152/description.xml",
            "http://\(host):1780/dmr.xml",
            "http://\(host):7000/rootDesc.xml",
        ]
        probeDLNA(urls: probeURLs, index: 0, host: host, mediaURL: mediaURL)
    }

    private func probeDLNA(urls: [String], index: Int, host: String, mediaURL: URL) {
        guard index < urls.count else {
            castLog("[AirPlay] No DLNA endpoint found on \(host)")
            DispatchQueue.main.async {
                self.delegate?.airplayCastDidFail("TV does not support DLNA casting. Try Control Center → Screen Mirroring instead.")
            }
            return
        }

        guard let url = URL(string: urls[index]) else {
            probeDLNA(urls: urls, index: index + 1, host: host, mediaURL: mediaURL)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        castLog("[AirPlay] Probing DLNA: \(urls[index])")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  let xml = String(data: data, encoding: .utf8),
                  (xml.contains("AVTransport") || xml.contains("MediaRenderer")) else {
                self?.probeDLNA(urls: urls, index: index + 1, host: host, mediaURL: mediaURL)
                return
            }

            castLog("[AirPlay] Found DLNA at \(urls[index])")
            let controlURL = self.parseDLNAControlURL(from: xml, host: host)
            castLog("[AirPlay] DLNA control URL: \(controlURL)")
            self.dlnaControlURL = controlURL
            self.sendDLNASetURI(controlURL: controlURL, mediaURL: mediaURL)
        }.resume()
    }

    private func parseDLNAControlURL(from xml: String, host: String) -> String {
        let serviceBlock: String? = {
            guard let avIdx = xml.range(of: "AVTransport") else { return nil }
            let before = xml[..<avIdx.lowerBound]
            guard let serviceStart = before.range(of: "<service>", options: .backwards) else { return nil }
            let afterService = xml[serviceStart.lowerBound...]
            guard let serviceEnd = afterService.range(of: "</service>") else { return nil }
            return String(afterService[..<serviceEnd.upperBound])
        }()

        if let block = serviceBlock,
           let ctrlStart = block.range(of: "<controlURL>"),
           let ctrlEnd = block[ctrlStart.upperBound...].range(of: "</controlURL>") {
            let path = String(block[ctrlStart.upperBound..<ctrlEnd.lowerBound])
            let port = { () -> Int in
                for p in [9197, 8080, 49152, 1780] {
                    if xml.contains(":\(p)") || xml.contains("localhost:\(p)") { return p }
                }
                return 9197
            }()
            if path.hasPrefix("http") { return path }
            return "http://\(host):\(port)\(path)"
        }

        return "http://\(host):9197/upnp/control/AVTransport1"
    }

    private func sendDLNASetURI(controlURL: String, mediaURL: URL) {
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>\(mediaURL.absoluteString)</CurrentURI>
              <CurrentURIMetaData></CurrentURIMetaData>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """

        sendDLNAAction(controlURL: controlURL, action: "SetAVTransportURI", body: body) { [weak self] success in
            if success {
                castLog("[AirPlay] SetAVTransportURI success, sending Play")
                self?.sendDLNAAction(controlURL: controlURL, action: "Play", body: self?.dlnaPlayBody ?? "") { playOK in
                    DispatchQueue.main.async {
                        if playOK {
                            self?.delegate?.airplayCastDidStartPlaying()
                        } else {
                            self?.delegate?.airplayCastDidFail("TV rejected playback")
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self?.delegate?.airplayCastDidFail("Failed to send media to TV")
                }
            }
        }
    }

    private func sendDLNAAction(controlURL: String, action: String, body: String, completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: controlURL) else {
            completion?(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = error == nil && code >= 200 && code < 300
            castLog("[AirPlay] DLNA \(action): HTTP \(code) \(ok ? "OK" : "FAIL")")
            completion?(ok)
        }.resume()
    }

    // MARK: - DLNA Body Templates

    private var dlnaPlayBody: String {
        """
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
    }

    private var dlnaPauseBody: String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Pause>
          </s:Body>
        </s:Envelope>
        """
    }

    private var dlnaStopBody: String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
          <s:Body>
            <u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
            </u:Stop>
          </s:Body>
        </s:Envelope>
        """
    }
}

// MARK: - Bonjour Discovery

extension AirPlayCastManager: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pendingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        pendingServices.removeAll { $0 == service }
        let id = service.name
        devices.removeAll { $0.id == id }
        delegate?.airplayCastDidRemove(id)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        castLog("[AirPlay] Browse failed: \(errorDict)")
    }
}

extension AirPlayCastManager: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses else { return }

        for data in addresses {
            let family = data.withUnsafeBytes { ptr -> sa_family_t in
                ptr.load(as: sockaddr.self).sa_family
            }
            guard family == sa_family_t(AF_INET) else { continue }

            let ip = data.withUnsafeBytes { ptr -> String in
                var addr = ptr.load(as: sockaddr_in.self)
                return String(cString: inet_ntoa(addr.sin_addr))
            }

            var name = sender.name
            if let txtData = sender.txtRecordData() {
                let txt = NetService.dictionary(fromTXTRecord: txtData)
                if let fnData = txt["fn"], let fn = String(data: fnData, encoding: .utf8) {
                    name = fn
                }
            }

            let device = CastDevice(
                id: sender.name,
                name: name,
                type: .airplay,
                host: ip,
                port: sender.port > 0 ? sender.port : 7000
            )

            if !devices.contains(where: { $0.id == device.id }) {
                devices.append(device)
                castLog("[AirPlay] Discovered: \(name) at \(ip):\(device.port)")
                delegate?.airplayCastDidDiscover(device)
            }
            break
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        castLog("[AirPlay] Failed to resolve: \(sender.name)")
    }
}
