/// Discovers Chromecast devices via Bonjour (_googlecast._tcp) and lists them in the menu.
/// Extracts the friendly name from the TXT record's "fn" key, falling back to
/// stripping the UUID suffix from the mDNS service name.
import Cocoa

class ChromecastMenuDelegate: NSObject, NSMenuDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = ChromecastMenuDelegate()

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvedDevices: [(name: String, host: String, port: Int)] = []

    override init() {
        super.init()
        startDiscovery()
    }

    private func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_googlecast._tcp.", inDomain: "local.")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if resolvedDevices.isEmpty {
            let scanning = NSMenuItem(title: L("Scanning…"), action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
            startDiscovery()
        } else {
            for device in resolvedDevices {
                let item = menu.addItem(withTitle: device.name, action: #selector(AppDelegate.castToChromecast(_:)), keyEquivalent: "")
                item.representedObject = device
            }
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        resolvedDevices.removeAll { $0.host == service.hostName }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var host = sender.hostName ?? sender.name
        // Strip trailing dot from mDNS hostname
        if host.hasSuffix(".") { host = String(host.dropLast()) }

        // Try to extract the IPv4 address directly from the resolved addresses
        if let addresses = sender.addresses {
            for addrData in addresses {
                addrData.withUnsafeBytes { ptr in
                    guard let sa = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                    if sa.pointee.sa_family == UInt8(AF_INET) {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                            host = String(cString: hostname)
                        }
                    }
                }
            }
        }

        let friendlyName = Self.friendlyName(for: sender)
        if !resolvedDevices.contains(where: { $0.host == host }) {
            resolvedDevices.append((name: friendlyName, host: host, port: sender.port))
        }
    }

    static func friendlyName(for service: NetService) -> String {
        // Try TXT record "fn" (friendly name) key first
        if let txtData = service.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let fnData = dict["fn"], let fn = String(data: fnData, encoding: .utf8), !fn.isEmpty {
                return fn
            }
        }
        // Fall back to stripping UUID suffix (e.g. "S90F-2ab6a79c..." → "S90F")
        let raw = service.name
        if let dashIdx = raw.firstIndex(of: "-") {
            let suffix = raw[raw.index(after: dashIdx)...]
            if suffix.count > 20 {
                return String(raw[..<dashIdx])
            }
        }
        return raw
    }
}
