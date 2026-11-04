import AppKit

/// Generates a short original radar-style pulse as PCM audio. Keeping the sound
/// procedural avoids bundling or copying a proprietary system ringtone.
enum RadarAlarmSound {
    static func make() -> NSSound? {
        let sampleRate = 44_100
        let duration = 1.8
        let frameCount = Int(Double(sampleRate) * duration)
        let pulses: [(start: Double, frequency: Double)] = [
            (0.00, 720), (0.18, 900), (0.36, 1_080),
            (0.82, 720), (1.00, 900), (1.18, 1_080)
        ]
        var samples = [Int16](repeating: 0, count: frameCount)

        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            var value = 0.0
            for pulse in pulses {
                let local = time - pulse.start
                guard local >= 0, local < 0.14 else { continue }
                let attack = min(1, local / 0.008)
                let release = max(0, 1 - local / 0.14)
                let envelope = attack * release * release
                let fundamental = sin(2 * .pi * pulse.frequency * local)
                let shimmer = 0.22 * sin(2 * .pi * pulse.frequency * 2.01 * local)
                value += envelope * (fundamental + shimmer)
            }
            let limited = max(-1, min(1, value * 0.46))
            samples[frame] = Int16(limited * Double(Int16.max))
        }

        var data = Data()
        let byteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        appendASCII("RIFF", to: &data)
        append(UInt32(36) + byteCount, to: &data)
        appendASCII("WAVEfmt ", to: &data)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data) // PCM
        append(UInt16(1), to: &data) // mono
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        appendASCII("data", to: &data)
        append(byteCount, to: &data)
        for sample in samples { append(UInt16(bitPattern: sample), to: &data) }

        return NSSound(data: data)
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
