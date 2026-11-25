import Foundation
import AVFoundation
import WaltzCore

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty { print("用法：WaltzInspect 图片路径 [x,y,w,h]\n或：WaltzInspect --video 录屏.mov 输出目录 [开始秒] [间隔秒] [数量]"); exit(0) }
do {
    if args[0] == "--video" {
        guard args.count >= 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 2100)
        try FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)
        let start = args.count > 3 ? Double(args[3]) ?? 0 : 0
        let step = args.count > 4 ? Double(args[4]) ?? 15 : 15
        let count = args.count > 5 ? Int(args[5]) ?? 12 : 12
        for i in 0..<min(count, 600) {
            let seconds = start + Double(i) * step
            let image = try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
            let path = String(format: "%@/%06.1f.png", args[2], seconds)
            try writePNG(image, path: path)
            print(path)
        }
    } else {
        var image = try loadImage(args[0])
        if args.count > 1 {
            let r = args[1].split(separator: ",").compactMap { Double($0) }
            if r.count == 4, let cropped = cropImage(image, rect: UnitRect(x:r[0], y:r[1], width:r[2], height:r[3])) { image = cropped }
        }
        let observation = try VisionReader(database: GuideDatabase.bundled()).read(image)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: try encoder.encode(observation), encoding: .utf8)!)
    }
} catch { fputs("\(error)\n", stderr); exit(1) }
