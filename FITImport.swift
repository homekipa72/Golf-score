import Foundation
import SwiftData

struct RoutePoint: Codable {
    var t: Double          // Unix time (초)
    var lat: Double?
    var lon: Double?
    var alt: Double?
    var hr: Int?
}

struct FITActivityData {
    var samples: [RoutePoint] = []
    var sport: Int?
    var startTime: Date?
    var elapsedSeconds: Double?
    var distanceMeters: Double?
    var calories: Int?
    var avgHR: Int?
    var maxHR: Int?
}

enum FITError: LocalizedError {
    case invalidFile, noData
    var errorDescription: String? {
        switch self {
        case .invalidFile: return "FIT 파일 형식이 아닙니다."
        case .noData: return "파일에서 활동 데이터를 찾지 못했습니다."
        }
    }
}

/// 외부 라이브러리 없는 최소 FIT 디코더 (record, session 메시지만 읽음)
enum FITDecoder {
    private struct MsgDef {
        let global: Int
        let big: Bool
        let fields: [(num: Int, size: Int)]
        let devBytes: Int
    }

    private static let fitEpoch: TimeInterval = 631_065_600  // 1989-12-31 UTC

    private static func readUInt(_ b: [UInt8], _ off: Int, _ size: Int, big: Bool) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<size {
            let byte = UInt64(b[off + (big ? i : size - 1 - i)])
            v = (v << 8) | byte
        }
        return v
    }

    private static func degrees(_ raw: UInt64) -> Double {
        Double(Int32(bitPattern: UInt32(raw))) * 180.0 / 2_147_483_648.0
    }

    static func decode(_ data: Data) throws -> FITActivityData {
        let b = [UInt8](data)
        guard b.count >= 14, b[8] == 0x2E, b[9] == 0x46, b[10] == 0x49, b[11] == 0x54 else {
            throw FITError.invalidFile
        }
        let headerSize = Int(b[0])
        guard headerSize >= 12, b.count > headerSize else { throw FITError.invalidFile }
        let dataSize = Int(readUInt(b, 4, 4, big: false))
        let end = min(headerSize + dataSize, b.count)

        var pos = headerSize
        var defs: [Int: MsgDef] = [:]
        var out = FITActivityData()
        var lastTS: UInt32 = 0
        var gotSession = false

        while pos < end {
            let header = b[pos]
            pos += 1

            // 정의 메시지
            if header & 0x80 == 0 && header & 0x40 != 0 {
                let local = Int(header & 0x0F)
                guard pos + 5 <= end else { break }
                let big = b[pos + 1] == 1
                let global = Int(readUInt(b, pos + 2, 2, big: big))
                let n = Int(b[pos + 4])
                pos += 5
                guard pos + n * 3 <= end else { break }
                var fields: [(num: Int, size: Int)] = []
                for i in 0..<n { fields.append((Int(b[pos + i * 3]), Int(b[pos + i * 3 + 1]))) }
                pos += n * 3
                var dev = 0
                if header & 0x20 != 0 {
                    guard pos < end else { break }
                    let m = Int(b[pos]); pos += 1
                    guard pos + m * 3 <= end else { break }
                    for i in 0..<m { dev += Int(b[pos + i * 3 + 1]) }
                    pos += m * 3
                }
                defs[local] = MsgDef(global: global, big: big, fields: fields, devBytes: dev)
                continue
            }

            // 데이터 메시지 (일반 / 압축 타임스탬프)
            let compressed = header & 0x80 != 0
            let local = compressed ? Int((header >> 5) & 0x03) : Int(header & 0x0F)
            guard let def = defs[local] else { break }
            let total = def.fields.reduce(0) { $0 + $1.size } + def.devBytes
            guard pos + total <= end else { break }

            var vals: [Int: UInt64] = [:]
            var p = pos
            for f in def.fields {
                if f.size == 1 || f.size == 2 || f.size == 4 {
                    let raw = readUInt(b, p, f.size, big: def.big)
                    let invalid: UInt64 = f.size == 1 ? 0xFF : (f.size == 2 ? 0xFFFF : 0xFFFF_FFFF)
                    if raw != invalid { vals[f.num] = raw }
                }
                p += f.size
            }
            pos += total

            if compressed {
                let offset = UInt32(header & 0x1F)
                var ts = (lastTS & 0xFFFF_FFE0) | offset
                if offset < (lastTS & 0x1F) { ts += 0x20 }
                lastTS = ts
                vals[253] = UInt64(ts)
            } else if let t = vals[253] {
                lastTS = UInt32(t)
            }

            switch def.global {
            case 20: // record
                guard let ts = vals[253] else { continue }
                var s = RoutePoint(t: fitEpoch + Double(ts))
                if let la = vals[0], la != 0x7FFF_FFFF, let lo = vals[1], lo != 0x7FFF_FFFF {
                    s.lat = degrees(la)
                    s.lon = degrees(lo)
                }
                if let a = vals[78] { s.alt = Double(a) / 5.0 - 500.0 }
                else if let a = vals[2] { s.alt = Double(a) / 5.0 - 500.0 }
                if let h = vals[3] { s.hr = Int(h) }
                if s.lat != nil || s.hr != nil { out.samples.append(s) }

            case 18: // session (첫 번째만 사용)
                guard !gotSession else { continue }
                gotSession = true
                if let t = vals[2] { out.startTime = Date(timeIntervalSince1970: fitEpoch + Double(t)) }
                if let s = vals[5] { out.sport = Int(s) }
                if let e = vals[7] { out.elapsedSeconds = Double(e) / 1000.0 }
                if let d = vals[9] { out.distanceMeters = Double(d) / 100.0 }
                if let c = vals[11] { out.calories = Int(c) }
                if let a = vals[16] { out.avgHR = Int(a) }
                if let m = vals[17] { out.maxHR = Int(m) }

            default: break
            }
        }

        guard gotSession || !out.samples.isEmpty else { throw FITError.noData }
        return out
    }
}

extension WatchActivity {
    static func sportName(_ code: Int?) -> String {
        switch code {
        case 25: return "골프"
        case 1: return "러닝"
        case 2: return "자전거"
        case 11: return "걷기"
        case .some(let c): return "기타(\(c))"
        case .none: return "알 수 없음"
        }
    }

    /// 같은 시작 시각이 이미 있으면 nil 반환 (중복 방지)
    @discardableResult
    static func importFIT(from url: URL, into context: ModelContext) throws -> WatchActivity? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let fit = try FITDecoder.decode(try Data(contentsOf: url))
        let firstSample = fit.samples.first.map { Date(timeIntervalSince1970: $0.t) }
        guard let start = fit.startTime ?? firstSample else { throw FITError.noData }

        let dup = try context.fetch(FetchDescriptor<WatchActivity>(
            predicate: #Predicate { $0.startTime == start }))
        if !dup.isEmpty { return nil }

        var duration = fit.elapsedSeconds ?? 0
        if duration == 0, let f = fit.samples.first, let l = fit.samples.last { duration = l.t - f.t }

        let activity = WatchActivity(
            startTime: start,
            sport: sportName(fit.sport),
            durationSeconds: duration,
            distanceMeters: fit.distanceMeters ?? 0,
            calories: fit.calories ?? 0,
            avgHeartRate: fit.avgHR ?? 0,
            maxHeartRate: fit.maxHR ?? 0,
            routeData: try? JSONEncoder().encode(fit.samples))
        context.insert(activity)
        return activity
    }
}
