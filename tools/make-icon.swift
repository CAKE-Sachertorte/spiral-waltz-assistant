import AppKit
let folder = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let image = NSImage(size: NSSize(width:size,height:size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(calibratedRed:0.20,green:0.14,blue:0.24,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:0,y:0,width:s,height:s),xRadius:s*0.22,yRadius:s*0.22).fill()
    let circle = NSBezierPath(ovalIn:NSRect(x:s*0.14,y:s*0.14,width:s*0.72,height:s*0.72))
    NSColor(calibratedRed:0.83,green:0.70,blue:0.52,alpha:1).setStroke();circle.lineWidth=s*0.018;circle.stroke()
    let heart = NSBezierPath()
    heart.move(to:NSPoint(x:s*0.5,y:s*0.26))
    heart.curve(to:NSPoint(x:s*0.24,y:s*0.62),controlPoint1:NSPoint(x:s*0.43,y:s*0.36),controlPoint2:NSPoint(x:s*0.17,y:s*0.50))
    heart.curve(to:NSPoint(x:s*0.50,y:s*0.70),controlPoint1:NSPoint(x:s*0.20,y:s*0.84),controlPoint2:NSPoint(x:s*0.43,y:s*0.87))
    heart.curve(to:NSPoint(x:s*0.76,y:s*0.62),controlPoint1:NSPoint(x:s*0.57,y:s*0.87),controlPoint2:NSPoint(x:s*0.80,y:s*0.84))
    heart.curve(to:NSPoint(x:s*0.50,y:s*0.26),controlPoint1:NSPoint(x:s*0.83,y:s*0.50),controlPoint2:NSPoint(x:s*0.57,y:s*0.36))
    heart.close()
    NSColor(calibratedRed:0.91,green:0.52,blue:0.64,alpha:1).setFill(); heart.fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    let png = bitmap.representation(using:.png,properties:[:])!
    let filename = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try png.write(to:URL(fileURLWithPath:folder).appendingPathComponent(filename))
}
for (from,to) in [(32,"icon_16x16@2x.png"),(64,"icon_32x32@2x.png"),(256,"icon_128x128@2x.png"),(512,"icon_256x256@2x.png")] {
    try FileManager.default.copyItem(atPath:"\(folder)/icon_\(from)x\(from).png",toPath:"\(folder)/\(to)")
}
