import Darwin
import Foundation

/// Facts about a process read straight from the kernel via libproc / sysctl.
/// No subprocess is spawned, so this is cheap enough to call every poll.
struct ProcessFacts: Sendable, Equatable {
    var pid: Int32
    var parentPID: Int32
    var uid: uid_t
    var startTime: Date
    var residentBytes: UInt64?
    var executablePath: String?
    var workingDirectory: String?
}

enum ProcessInspector {
    /// Returns nil if the process no longer exists or belongs to someone we can't inspect.
    static func facts(for pid: Int32) -> ProcessFacts? {
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        let start = Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000)
        return ProcessFacts(
            pid: pid,
            parentPID: Int32(bsd.pbi_ppid),
            uid: bsd.pbi_uid,
            startTime: start,
            residentBytes: residentBytes(for: pid),
            executablePath: executablePath(for: pid),
            workingDirectory: workingDirectory(for: pid)
        )
    }

    static func residentBytes(for pid: Int32) -> UInt64? {
        var task = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, size) == size else { return nil }
        return task.pti_resident_size
    }

    static func parentPID(of pid: Int32) -> Int32? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        return Int32(bsd.pbi_ppid)
    }

    static func workingDirectory(for pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    static func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE isn't imported into Swift
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The process's argv, read with `KERN_PROCARGS2`. Unlike `ps -o command=`, this keeps
    /// argument boundaries intact, so arguments containing spaces survive a restart.
    static func arguments(for pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: argc (Int32) | exec path \0 | padding \0... | argv[0] \0 ... argv[argc-1] \0 | env...
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // skip exec path
        while index < size, buffer[index] == 0 { index += 1 }   // skip padding

        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args.isEmpty ? nil : args
    }

    /// Whether a process with this pid currently exists (it may be a zombie).
    static func isAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
