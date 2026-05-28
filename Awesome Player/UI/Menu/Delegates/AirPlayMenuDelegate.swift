/// Discovers AirPlay devices via Bonjour (_airplay._tcp) and lists them in the menu.
/// Clicking a device triggers the AVRoutePickerView in the control bar.
import Cocoa

class AirPlayMenuDelegate: NSObject, NSMenuDelegate, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = AirPlayMenuDelegate()

    private var browser: NetServiceBrowser?
    private var services: [NetService] = []
    private var resolvedDevices: [(name: String, host: String)] = []

    override init() {
        super.init()
        startDiscovery()
    }

    private func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if resolvedDevices.isEmpty {
            let scanning = NSMenuItem(title: L("Scanning…"), action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
            // Restart discovery in case it timed out
            startDiscovery()
        } else {
            for device in resolvedDevices {
                menu.addItem(withTitle: device.name, action: #selector(AppDelegate.showAirPlay(_:)), keyEquivalent: "")
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
        resolvedDevices.removeAll { $0.name == service.name }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let host = sender.hostName ?? sender.name
        if !resolvedDevices.contains(where: { $0.name == name }) {
            resolvedDevices.append((name: name, host: host))
        }
    }
}
