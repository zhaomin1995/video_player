import Foundation
import Network

class CastingHTTPServer {
    private var listener: NWListener?
    private var servingFileURL: URL?
    private var port: UInt16 = 0

    func start(servingFile fileURL: URL, completion: @escaping (URL?) -> Void) {
        servingFileURL = fileURL

        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: .any)

            listener?.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if let port = self?.listener?.port?.rawValue {
                        self?.port = port
                        let localIP = self?.getLocalIPAddress() ?? "127.0.0.1"
                        let url = URL(string: "http://\(localIP):\(port)/media")
                        DispatchQueue.main.async {
                            completion(url)
                        }
                    }
                case .failed(let error):
                    wlog(.http, "HTTP server failed: \(error)")
                    DispatchQueue.main.async { completion(nil) }
                default:
                    break
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.start(queue: .global(qos: .userInitiated))
        } catch {
            wlog(.http, "Failed to start HTTP server: \(error)")
            completion(nil)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        servingFileURL = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] content, _, _, error in
            guard let data = content, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            self?.handleHTTPRequest(request, connection: connection)
        }
    }

    private func handleHTTPRequest(_ request: String, connection: NWConnection) {
        guard let fileURL = servingFileURL else {
            sendErrorResponse(connection: connection, status: 404)
            return
        }

        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64,
              fileSize > 0 else {
            sendErrorResponse(connection: connection, status: 404)
            return
        }

        // Parse Range header
        var rangeStart: UInt64 = 0
        var rangeEnd: UInt64 = fileSize - 1
        var hasRangeHeader = false

        if let rangeLine = request.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }) {
            hasRangeHeader = true
            let rangeValue = rangeLine.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            if rangeValue.hasPrefix("bytes=") {
                let byteRange = rangeValue.dropFirst(6)
                let parts = byteRange.components(separatedBy: "-")
                if let start = UInt64(parts[0]) {
                    rangeStart = start
                }
                if parts.count > 1, let end = UInt64(parts[1]) {
                    rangeEnd = min(end, fileSize - 1)
                }
            }
        }

        let contentLength = rangeEnd - rangeStart + 1
        let mimeType = mimeTypeForExtension(fileURL.pathExtension)

        let statusCode = hasRangeHeader ? 206 : 200
        let statusText = hasRangeHeader ? "Partial Content" : "OK"

        var headers = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        headers += "Content-Type: \(mimeType)\r\n"
        headers += "Content-Length: \(contentLength)\r\n"
        headers += "Accept-Ranges: bytes\r\n"
        headers += "Access-Control-Allow-Origin: *\r\n"
        // DLNA hints — Samsung MediaRenderers ignore the file without these.
        // OP=01 = both byte-seek and time-seek supported; the flags are the
        // standard fixed-size streamable profile.
        headers += "transferMode.dlna.org: Streaming\r\n"
        headers += "contentFeatures.dlna.org: DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\r\n"

        if statusCode == 206 {
            headers += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(fileSize)\r\n"
        }

        headers += "Connection: close\r\n"
        headers += "\r\n"

        let headerData = headers.data(using: .utf8) ?? Data()
        connection.send(content: headerData, completion: .contentProcessed { _ in })

        // Send file data
        if request.hasPrefix("HEAD") {
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            connection.cancel()
            return
        }

        fileHandle.seek(toFileOffset: rangeStart)
        sendFileChunks(fileHandle: fileHandle, connection: connection, remaining: contentLength)
    }

    private func sendFileChunks(fileHandle: FileHandle, connection: NWConnection, remaining: UInt64) {
        let chunkSize: Int = 65536
        let toRead = min(UInt64(chunkSize), remaining)
        guard toRead > 0 else {
            fileHandle.closeFile()
            connection.cancel()
            return
        }

        let data = fileHandle.readData(ofLength: Int(toRead))
        guard !data.isEmpty else {
            fileHandle.closeFile()
            connection.cancel()
            return
        }

        let newRemaining = remaining - UInt64(data.count)
        let isLast = newRemaining == 0

        connection.send(content: data, contentContext: isLast ? .finalMessage : .defaultMessage, isComplete: isLast, completion: .contentProcessed { [weak self] error in
            if error != nil || isLast {
                fileHandle.closeFile()
                if isLast { connection.cancel() }
            } else {
                self?.sendFileChunks(fileHandle: fileHandle, connection: connection, remaining: newRemaining)
            }
        })
    }

    private func sendErrorResponse(connection: NWConnection, status: Int) {
        let response = "HTTP/1.1 \(status) Error\r\nContent-Length: 0\r\n\r\n"
        connection.send(content: response.data(using: .utf8), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v": return "video/mp4"
        case "mkv": return "video/x-matroska"
        case "avi": return "video/x-msvideo"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "ts", "mts": return "video/mp2t"
        case "mp3": return "audio/mpeg"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        default: return "application/octet-stream"
        }
    }
}
