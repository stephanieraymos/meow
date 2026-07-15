import SwiftUI
import SceneKit

/// Renders a bundled animated `.usdz` cat on a transparent background, looping
/// its embedded animation. Framing uses the mesh's vertex centroid (the rig's
/// bounding box is unreliable). Loaded lazily — only on result screens — so the
/// board is never affected.
struct CatSceneView: UIViewRepresentable {
    let resource: String          // e.g. "sad_cat" (Meowdoku/Models/sad_cat.usdz)
    var angle: Float = 0.55
    /// Nudge the subject in-frame (fractions of the framing distance): + down, + right.
    var upFrac: Float = 0.07
    var rightFrac: Float = 0.09

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true

        guard let url = Bundle.main.url(forResource: resource, withExtension: "usdz"),
              let scene = try? SCNScene(url: url) else { return view }
        view.scene = scene

        // Soft two-light setup so PBR materials read well on any background.
        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 820
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 900
        key.eulerAngles = SCNVector3(-0.7, 0.6, 0)
        scene.rootNode.addChildNode(key)

        // Frame on the mesh vertex centroid; distance auto-scales from the spread.
        let (c, spread) = centroidAndSpread(scene.rootNode)
        let distance = max(spread * 3.9, 1)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.automaticallyAdjustsZRange = true
        cam.position = SCNVector3(c.x + sin(angle) * distance, c.y + distance * 0.08, c.z + cos(angle) * distance)
        cam.look(at: c)   // establishes orientation so worldUp/Right are valid
        let up = cam.worldUp, right = cam.worldRight
        let uo = distance * upFrac, ro = distance * rightFrac
        cam.look(at: SCNVector3(c.x + up.x * uo - right.x * ro,
                                c.y + up.y * uo - right.y * ro,
                                c.z + up.z * uo - right.z * ro))
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    /// Vertex centroid + RMS distance from it (robust to a few stray verts).
    private func centroidAndSpread(_ root: SCNNode) -> (SCNVector3, Float) {
        var sx: Float = 0, sy: Float = 0, sz: Float = 0, n: Float = 0
        func forEachVertex(_ body: (SCNVector3) -> Void) {
            root.enumerateHierarchy { node, _ in
                guard let geo = node.geometry else { return }
                for source in geo.sources(for: .vertex) {
                    let stride = source.dataStride, offset = source.dataOffset
                    let comps = source.componentsPerVector
                    source.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                        for i in 0..<source.vectorCount {
                            let p = raw.baseAddress!.advanced(by: i * stride + offset)
                                .assumingMemoryBound(to: Float32.self)
                            let v = SCNVector3(p[0], comps > 1 ? p[1] : 0, comps > 2 ? p[2] : 0)
                            body(node.convertPosition(v, to: nil))
                        }
                    }
                }
            }
        }
        forEachVertex { w in sx += w.x; sy += w.y; sz += w.z; n += 1 }
        guard n > 0 else { return (SCNVector3Zero, 100) }
        let c = SCNVector3(sx / n, sy / n, sz / n)
        var ss: Float = 0
        forEachVertex { w in
            let dx = w.x - c.x, dy = w.y - c.y, dz = w.z - c.z
            ss += dx*dx + dy*dy + dz*dz
        }
        return (c, (ss / n).squareRoot())
    }
}
