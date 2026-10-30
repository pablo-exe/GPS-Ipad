import Foundation

func decode(_ text: String) throws -> GPSFrame {
    let frame = try JSONDecoder().decode(GPSFrame.self, from: Data(text.utf8))
    try frame.validate()
    return frame
}
func rejected(_ text: String) {
    do { _ = try decode(text); fatalError("Accepted invalid frame: \(text)") } catch { }
}
let valid = #"{"v":1,"type":"fix","seq":1,"lat":40.4168,"lon":-3.7038,"accuracy":5,"age_ms":500}"#
let frame = try decode(valid)
let fix = ReceivedFix(frame: frame, receivedAt: 100, streamID: UUID())
precondition(fix.isFresh(at: 101.99))
precondition(!fix.isFresh(at: 102))
precondition(!fix.isFresh(at: 200))
let waiting = try decode(#"{"v":1,"type":"waiting"}"#)
precondition(waiting.type == "waiting")
rejected(valid.replacingOccurrences(of: "40.4168", with: "91"))
rejected(valid.replacingOccurrences(of: "-3.7038", with: "181"))
rejected(valid.replacingOccurrences(of: "\"age_ms\":500", with: "\"age_ms\":2500"))
rejected(valid.replacingOccurrences(of: "\"age_ms\":500", with: "\"age_ms\":-1"))
rejected(valid.replacingOccurrences(of: "\"accuracy\":5", with: "\"accuracy\":101"))
rejected(valid.replacingOccurrences(of: "\"accuracy\":5", with: "\"accuracy\":0"))
rejected(valid.replacingOccurrences(of: "\"v\":1", with: "\"v\":2"))
rejected(#"{"v":1,"type":"fix"}"#)
var buffer = LineBuffer()
let partial = try buffer.append(Data(valid.prefix(20).utf8))
precondition(partial.isEmpty)
let lines = try buffer.append(Data((valid.dropFirst(20) + "\n" + valid + "\r\n").utf8))
precondition(lines.count == 2)
for line in lines { let value = try JSONDecoder().decode(GPSFrame.self, from: line); try value.validate() }
do { _ = try buffer.append(Data(repeating: 65, count: 4097)); fatalError("Oversize accepted") } catch { }
var largeTerminated = LineBuffer()
do { _ = try largeTerminated.append(Data((String(repeating: "a", count: 4097) + "\n").utf8)); fatalError("Oversize line accepted") } catch { }
let mailbox = FixMailbox()
mailbox.put(fix)
precondition(mailbox.get()?.frame.seq == 1)
mailbox.put(nil)
precondition(mailbox.get() == nil)
print("PASS: NDJSON fragmentation/coalescing, validation, source age + monotonic expiry, bounded buffers and invalidation")
