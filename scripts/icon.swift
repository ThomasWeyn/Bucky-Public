import AppKit
let sizes: [(String,Int)] = [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)]
for (name,size) in sizes {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform();transform.scale(by:scale);transform.concat()
    NSColor(calibratedRed:0.19,green:0.39,blue:0.31,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:210,yRadius:210).fill()
    NSColor(calibratedRed:0.85,green:0.91,blue:0.78,alpha:1).setFill()
    for (i,h) in [180,320,470,580,400,260,140].enumerated() {
        NSBezierPath(roundedRect:NSRect(x:230+i*82,y:(1024-h)/2,width:48,height:h),xRadius:24,yRadius:24).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"Assets/Bucky.iconset/\(name).png"))
}
