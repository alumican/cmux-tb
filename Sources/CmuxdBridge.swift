import Foundation

/// Helpers for detecting cmuxd and generating cmux-bridge commands.
enum CmuxdBridge {
    /// Default port cmuxd listens on.
    static let defaultPort: UInt16 = 3778

    /// Whether bridge mode is enabled. Checks if cmuxd is reachable.
    static var isAvailable: Bool {
        // Check if cmux-bridge binary exists in the app bundle
        guard bridgeBinaryPath != nil else { return false }
        // Try a quick TCP connect to cmuxd
        return canConnect(port: defaultPort)
    }

    /// Path to the cmux-bridge binary in the app bundle or development build.
    static var bridgeBinaryPath: String? {
        // Check app bundle Resources/bin/ first
        if let bundlePath = Bundle.main.resourceURL?
            .appendingPathComponent("bin/cmux-bridge").path,
           FileManager.default.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }
        // Development fallback: check cmuxd/zig-out/bin/
        let devPath = Bundle.main.bundlePath
            .components(separatedBy: "/")
            .prefix(while: { $0 != "DerivedData" && $0 != "Build" })
            .joined(separator: "/")
        // Try relative to the project root
        let candidates = [
            "\(devPath)/cmuxd/zig-out/bin/cmux-bridge",
            NSHomeDirectory() + "/fun/cmuxterm3/cmuxd/zig-out/bin/cmux-bridge",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Generate the bridge command string for a new surface.
    static func command(port: UInt16 = defaultPort, sessionId: UInt32? = nil) -> String? {
        guard let binary = bridgeBinaryPath else { return nil }
        var cmd = "\(binary) --port \(port)"
        if let sid = sessionId {
            cmd += " --session \(sid)"
        }
        return cmd
    }

    /// Quick TCP connect check to see if cmuxd is listening.
    private static func canConnect(port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        // Set non-blocking for a quick timeout
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 { return true }
        if errno == EINPROGRESS {
            // Wait up to 100ms for connection
            var pollfd = Darwin.pollfd(fd: Int32(sock), events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollfd, 1, 100)
            if pollResult > 0 && (pollfd.revents & Int16(POLLOUT)) != 0 {
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &len)
                return error == 0
            }
        }
        return false
    }
}
