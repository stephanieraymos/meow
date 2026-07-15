import SwiftUI
import SceneKit

/// Renders a bundled animated `.usdz` cat on a transparent background, looping
/// its embedded animation. Framing uses the mesh's vertex centroid (the rig's
/// bounding box is unreliable). Loaded lazily — only on result screens — so the
/// board is never affected.
struct CatSceneView: UIViewRepresentable {
    let resource: String          // e.g. "sad_cat" (Meowdoku/Models/sad_cat.usdz)
    var distance: Float = 210
    var angle: Float = 0.55

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

        // Frame on the vertex centroid.
        let c = centroid(scene.rootNode)
        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.camera?.automaticallyAdjustsZRange = true
        cam.position = SCNVector3(c.x + sin(angle) * distance, c.y + distance * 0.08, c.z + cos(angle) * distance)
        cam.look(at: c)
        scene.rootNode.addChildNode(cam)
        view.pointOfView = cam
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private func centroid(_ root: SCNNode) -> SCNVector3 {
        var sx: Float = 0, sy: Float = 0, sz: Float = 0, n: Float = 0
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
                        let w = node.convertPosition(v, to: nil)
                        sx += w.x; sy += w.y; sz += w.z; n += 1
                    }
                }
            }
        }
        guard n > 0 else { return SCNVector3Zero }
        return SCNVector3(sx / n, sy / n, sz / n)
    }
}
