import Darwin
import Foundation
import TokensCore

/// Finds and stops running Claude Code CLI processes on this Mac.
enum ClaudeProcesses {
    /// PIDs of Claude Code processes owned by this user, other than Burnrate itself.
    static func running() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        let me = getpid()
        let uid = getuid()
        return pids.prefix(Int(count)).filter { pid in
            guard pid > 0, pid != me, owner(of: pid) == uid, let path = executablePath(pid) else { return false }
            return ClaudeProcessMatch.isClaudeCode(executablePath: path, arguments: arguments(pid))
        }
    }

    /// SIGTERM every Claude Code process, then SIGKILL the ones still alive after `wait`.
    /// Returns how many were asked to stop.
    static func stopAll(wait: TimeInterval) async -> Int {
        let pids = running()
        for pid in pids { kill(pid, SIGTERM) }
        guard !pids.isEmpty else { return 0 }
        let deadline = Date().addingTimeInterval(wait)
        var alive = pids
        while !alive.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            alive = alive.filter { kill($0, 0) == 0 }
        }
        for pid in alive { kill(pid, SIGKILL) }
        return pids.count
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func owner(of pid: pid_t) -> uid_t? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return info.pbsi_uid
    }

    private static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return [] }
        return ClaudeProcessMatch.arguments(fromProcArgs: Array(bytes.prefix(size)))
    }
}
