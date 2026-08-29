import Foundation
import AppKit

let shotPath = CommandLine.arguments[1]
let boundsArg = CommandLine.arguments[2]
guard let img = NSImage(contentsOfFile: shotPath),
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else { exit(1) }
let w = rep.pixelsWide, h = rep.pixelsHigh
struct P { var x: Int; var y: Int }
var blues: [P] = [], grays: [P] = []
// Centered alert only. Exclude Machines Start/FAB (right/lower chrome).
let y0 = h * 38 / 100, y1 = h * 62 / 100
let x0 = w * 22 / 100, x1 = w * 78 / 100
for y in stride(from: y0, through: y1, by: 3) {
  for x in stride(from: x0, through: x1, by: 3) {
    guard let c = rep.colorAt(x: x, y: y) else { continue }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getRed(&r, green: &g, blue: &b, alpha: &a)
    if b > 0.70 && r < 0.40 && g > 0.35 && g < 0.70 && b > g {
      blues.append(P(x: x, y: y))
    }
    let maxc = max(r, g, b), minc = min(r, g, b)
    if maxc > 0.75 && minc > 0.65 && (maxc - minc) < 0.12 {
      grays.append(P(x: x, y: y))
    }
  }
}
func center(_ ps: [P]) -> (Int, Int)? {
  guard !ps.isEmpty else { return nil }
  return (ps.map(\.x).reduce(0, +) / ps.count, ps.map(\.y).reduce(0, +) / ps.count)
}
guard let blue = center(blues) else { exit(0) }
let below = grays.filter {
  $0.y > blue.1 + 40 &&
    $0.y < blue.1 + h * 12 / 100 &&
    abs($0.x - blue.0) < w / 6
}
// Require the gray Allow Paste row. Guessing 11% below a lone blue blob
// often hits Machines Start / Edit.
guard let allow = center(below) else { exit(0) }
let parts = boundsArg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
guard parts.count == 4 else { exit(3) }
let wx = parts[0], wy = parts[1], ww = parts[2], wh = parts[3]
let sx = wx + Double(allow.0) * ww / Double(w)
let sy = wy + Double(allow.1) * wh / Double(h)
print("\(sx) \(sy)")
