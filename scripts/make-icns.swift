import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-icns.swift <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndian(_ value: UInt32) -> Data {
    var number = value.bigEndian
    return Data(bytes: &number, count: MemoryLayout<UInt32>.size)
}

var chunks = Data()
for (type, filename) in entries {
    let data = try Data(contentsOf: iconset.appendingPathComponent(filename))
    chunks.append(type.data(using: .ascii)!)
    chunks.append(bigEndian(UInt32(data.count + 8)))
    chunks.append(data)
}

var result = Data("icns".utf8)
result.append(bigEndian(UInt32(chunks.count + 8)))
result.append(chunks)
try result.write(to: output, options: .atomic)
