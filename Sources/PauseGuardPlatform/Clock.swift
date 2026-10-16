import Foundation
import Darwin

public struct ClockSnapshot: Codable, Equatable, Sendable {
    public var continuousUptime: TimeInterval
    public var bootID: String
    public var wallDate: Date

    public init(continuousUptime: TimeInterval, bootID: String, wallDate: Date) {
        self.continuousUptime = continuousUptime
        self.bootID = bootID
        self.wallDate = wallDate
    }
    var isValid: Bool {
        continuousUptime.isFinite && continuousUptime >= 0 && !bootID.isEmpty && wallDate.timeIntervalSince1970.isFinite
    }
}

public enum SystemClock {
    private static let fallbackBootID = "process-" + UUID().uuidString
    /// mach_continuous_time advances during system sleep, unlike systemUptime.
    public static func snapshot() -> ClockSnapshot {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let seconds = Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
        var size = 0
        sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        let result = sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0)
        // An unavailable identity deliberately cannot match a saved boot.
        let bootID = result == 0 ? String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : fallbackBootID
        return ClockSnapshot(continuousUptime: seconds, bootID: bootID, wallDate: Date())
    }
}
