import Foundation

enum CastDeviceType {
    case airplay
    case chromecast
    case dlna
}

struct CastDevice {
    let id: String
    let name: String
    let type: CastDeviceType
    let host: String
    let port: Int
}

enum CastState {
    case disconnected
    case connecting
    case connected(CastDevice)
    case playing(CastDevice)
}

protocol CastingManagerDelegate: AnyObject {
    func castingManager(_ manager: CastingManager, didDiscoverDevice device: CastDevice)
    func castingManager(_ manager: CastingManager, didRemoveDevice deviceId: String)
    func castingManager(_ manager: CastingManager, didChangeState state: CastState)
    func castingManager(_ manager: CastingManager, didUpdatePosition position: Double, duration: Double)
    func castingManager(_ manager: CastingManager, didFail message: String)
}

class CastingManager {
    weak var delegate: CastingManagerDelegate?

    private let chromecastManager = ChromecastManager()
    private let dlnaManager = DLNAManager()
    let airplayManager = AirPlayCastManager()
    private let httpServer = CastingHTTPServer()

    private(set) var state: CastState = .disconnected
    private(set) var discoveredDevices: [CastDevice] = []

    func startDiscovery() {
        chromecastManager.delegate = self
        dlnaManager.delegate = self
        airplayManager.delegate = self
        chromecastManager.startDiscovery()
        dlnaManager.startDiscovery()
        airplayManager.startDiscovery()
    }

    func stopDiscovery() {
        chromecastManager.stopDiscovery()
        dlnaManager.stopDiscovery()
        airplayManager.stopDiscovery()
    }

    func startAirPlayDiscovery() {
        airplayManager.delegate = self
        airplayManager.startDiscovery()
    }

    func connect(to device: CastDevice) {
        state = .connecting
        delegate?.castingManager(self, didChangeState: state)

        switch device.type {
        case .chromecast:
            chromecastManager.connect(to: device)
        case .dlna:
            dlnaManager.connect(to: device)
        case .airplay:
            break
        }
    }

    func cast(fileURL: URL, to device: CastDevice) {
        switch device.type {
        case .airplay:
            airplayManager.cast(fileURL: fileURL, httpServer: httpServer, to: device)
        default:
            castLog("[CastingManager] Starting HTTP server for: \(fileURL.path)")
            httpServer.start(servingFile: fileURL) { [weak self] serverURL in
                guard let self = self, let url = serverURL else {
                    castLog("[CastingManager] HTTP server failed to start")
                    return
                }
                castLog("[CastingManager] HTTP server ready at: \(url.absoluteString)")

                switch device.type {
                case .chromecast:
                    self.chromecastManager.loadMedia(url: url, on: device)
                case .dlna:
                    self.dlnaManager.loadMedia(url: url, on: device)
                case .airplay:
                    break
                }

                self.state = .playing(device)
                self.delegate?.castingManager(self, didChangeState: self.state)
            }
        }
    }

    func pause() {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.pause()
            case .dlna: dlnaManager.pause()
            case .airplay: airplayManager.pause()
            }
        default: break
        }
    }

    func resume() {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.play()
            case .dlna: dlnaManager.play()
            case .airplay: airplayManager.play()
            }
        default: break
        }
    }

    func seek(to position: Double) {
        switch state {
        case .playing(let device):
            switch device.type {
            case .chromecast: chromecastManager.seek(to: position)
            case .dlna: dlnaManager.seek(to: position)
            case .airplay: airplayManager.seek(to: position)
            }
        default: break
        }
    }

    func stop() {
        switch state {
        case .playing(let device), .connected(let device):
            switch device.type {
            case .chromecast: chromecastManager.stop()
            case .dlna: dlnaManager.stop()
            case .airplay: airplayManager.stop()
            }
        default: break
        }
        httpServer.stop()
        state = .disconnected
        delegate?.castingManager(self, didChangeState: state)
    }

    func disconnect() {
        stop()
    }
}

extension CastingManager: ChromecastManagerDelegate {
    func chromecastDidDiscover(_ device: CastDevice) {
        discoveredDevices.append(device)
        delegate?.castingManager(self, didDiscoverDevice: device)
    }

    func chromecastDidRemove(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        delegate?.castingManager(self, didRemoveDevice: deviceId)
    }

    func chromecastDidConnect(_ device: CastDevice) {
        state = .connected(device)
        castLog("[CastingManager] Chromecast connected: \(device.name) at \(device.host):\(device.port)")
        delegate?.castingManager(self, didChangeState: state)
    }

    func chromecastDidUpdatePosition(_ position: Double, duration: Double) {
        delegate?.castingManager(self, didUpdatePosition: position, duration: duration)
    }
}

extension CastingManager: DLNAManagerDelegate {
    func dlnaDidDiscover(_ device: CastDevice) {
        discoveredDevices.append(device)
        delegate?.castingManager(self, didDiscoverDevice: device)
    }

    func dlnaDidRemove(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        delegate?.castingManager(self, didRemoveDevice: deviceId)
    }

    func dlnaDidConnect(_ device: CastDevice) {
        state = .connected(device)
        delegate?.castingManager(self, didChangeState: state)
    }

    func dlnaDidUpdatePosition(_ position: Double, duration: Double) {
        delegate?.castingManager(self, didUpdatePosition: position, duration: duration)
    }
}

extension CastingManager: AirPlayCastManagerDelegate {
    func airplayCastDidDiscover(_ device: CastDevice) {
        discoveredDevices.append(device)
        delegate?.castingManager(self, didDiscoverDevice: device)
    }

    func airplayCastDidRemove(_ deviceId: String) {
        discoveredDevices.removeAll { $0.id == deviceId }
        delegate?.castingManager(self, didRemoveDevice: deviceId)
    }

    func airplayCastDidConnect(_ device: CastDevice) {
        state = .connected(device)
        castLog("[CastingManager] AirPlay connected: \(device.name)")
        delegate?.castingManager(self, didChangeState: state)
    }

    func airplayCastDidStartPlaying() {
        if case .connected(let device) = state {
            state = .playing(device)
            delegate?.castingManager(self, didChangeState: state)
        }
    }

    func airplayCastDidFail(_ message: String) {
        castLog("[CastingManager] AirPlay failed: \(message)")
        delegate?.castingManager(self, didFail: message)
    }
}
