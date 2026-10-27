import Darwin
import Foundation
import MachO
import UIKit

/// Native crash capture for remote reports. A crash ends the process before `AppLog` can say
/// anything, so a submitted log only showed the relaunch. On a fatal signal (Swift runtime traps,
/// force-unwraps and `fatalError` included, arrive as SIGTRAP) or an uncaught Objective-C
/// exception the handler appends the backtrace to `Library/Caches/strmr_last_crash.log`; the next
/// launch copies it into the app log under `[crash]` and deletes it, so it rides the next upload.
/// Each frame carries its image's load address, so a release build symbolicates with
/// `atos -o StrmrTV.app.dSYM/Contents/Resources/DWARF/StrmrTV -l <base> <address>`.
enum CrashReporter {
    private static let log = AppLog(category: "crash")
    private static let path: String = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("strmr_last_crash.log").path
    }()
    private static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    @MainActor
    static func install() {
        reportPreviousCrash()
        let image = mainImage()
        log.notice("launch \(Config.fullVersion) \(Config.osVersion) image \(image)")

        // The handler may not allocate, so everything it writes is prepared here.
        crashPath = strdup(path)
        let header = "=== native crash: StrmrTV \(Config.fullVersion) \(Config.osVersion) image \(image)\n"
        crashHeader = strdup(header)
        crashFrames = .allocate(capacity: Int(maxFrames))

        NSSetUncaughtExceptionHandler(crashExceptionHandler)

        for sig in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_sigaction = crashSignalHandler
            action.sa_flags = SA_SIGINFO
            sigemptyset(&action.sa_mask)
            sigaction(sig, &action, nil)
        }
    }

    /// Copies the previous run's crash file into the log, then deletes it.
    private static func reportPreviousCrash() {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: path)
        log.error("the previous run crashed; its report follows")
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            log.error(String(line))
        }
    }

    /// Appends the exception to the crash file; the abort that follows adds its own signal
    /// backtrace after it.
    fileprivate static func record(_ exception: NSException) {
        var text = crashHeader.map { String(cString: $0) } ?? ""
        text += "uncaught exception \(exception.name.rawValue): \(exception.reason ?? "no reason")\n"
        for (index, symbol) in exception.callStackSymbols.enumerated() {
            text += "\(symbol)\(imageBase(of: exception.callStackReturnAddresses[safe: index]))\n"
        }
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data(text.utf8))
        handle.closeFile()
    }

    private static func imageBase(of address: NSNumber?) -> String {
        guard let address, let pointer = UnsafeRawPointer(bitPattern: address.uintValue) else { return "" }
        var info = Dl_info()
        guard dladdr(pointer, &info) != 0, let base = info.dli_fbase else { return "" }
        return " base=0x" + String(UInt(bitPattern: base), radix: 16)
    }

    /// The app binary's load address and UUID, which match a frame to the archive's dSYM.
    private static func mainImage() -> String {
        guard let header = _dyld_get_image_header(0) else { return "unknown" }
        let base = "0x" + String(UInt(bitPattern: header), radix: 16)
        var command = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<header.pointee.ncmds {
            let load = command.assumingMemoryBound(to: load_command.self).pointee
            if load.cmd == LC_UUID {
                let uuid = command.assumingMemoryBound(to: uuid_command.self).pointee.uuid
                return "base=\(base) uuid=\(UUID(uuid: uuid).uuidString)"
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        return "base=\(base)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: Handlers

private func crashExceptionHandler(_ exception: NSException) {
    CrashReporter.record(exception)
}

// Prepared by `install()`; the handler only reads them.
private let maxFrames: Int32 = 128
nonisolated(unsafe) private var crashPath: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var crashHeader: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>?

/// Writes the faulting thread's backtrace with write(2) only, then restores the default action
/// and re-raises, so the system still records its own crash report.
private func crashSignalHandler(_ sig: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _: UnsafeMutableRawPointer?) {
    if let crashPath, let crashFrames {
        let fd = open(crashPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        if fd >= 0 {
            if let crashHeader { _ = write(fd, crashHeader, strlen(crashHeader)) }
            writeText(fd, "signal ")
            writeNumber(fd, UInt(sig), radix: 10)
            writeText(fd, " fault address 0x")
            writeNumber(fd, UInt(bitPattern: info?.pointee.si_addr), radix: 16)
            writeText(fd, " time ")
            writeNumber(fd, UInt(max(time(nil), 0)), radix: 10)
            writeText(fd, "\n")
            let count = backtrace(crashFrames, maxFrames)
            backtrace_symbols_fd(crashFrames, count, fd)
            // The load address of each frame's image, for atos.
            writeText(fd, "frame image bases:\n")
            for index in 0..<Int(count) {
                var image = Dl_info()
                guard let frame = crashFrames[index], dladdr(frame, &image) != 0 else { continue }
                writeNumber(fd, UInt(index), radix: 10)
                writeText(fd, " 0x")
                writeNumber(fd, UInt(bitPattern: frame), radix: 16)
                writeText(fd, " base=0x")
                writeNumber(fd, UInt(bitPattern: image.dli_fbase), radix: 16)
                writeText(fd, "\n")
            }
            close(fd)
        }
    }
    signal(sig, SIG_DFL)
    raise(sig)
}

private func writeText(_ fd: Int32, _ text: StaticString) {
    _ = write(fd, text.utf8Start, text.utf8CodeUnitCount)
}

/// Formats `value` on the stack; no allocation.
private func writeNumber(_ fd: Int32, _ value: UInt, radix: UInt) {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 24) { buffer in
        var index = buffer.count
        var rest = value
        repeat {
            index -= 1
            let digit = UInt8(rest % radix)
            buffer[index] = digit < 10 ? 48 + digit : 87 + digit
            rest /= radix
        } while rest > 0
        _ = write(fd, buffer.baseAddress! + index, buffer.count - index)
    }
}
