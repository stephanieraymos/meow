import Foundation

/// A selectable "cat piece" — the glyph placed on the board. Purely cosmetic.
struct CatStyle: Identifiable, Equatable {
    let id: String
    let name: String
    let glyph: String
}

enum CatStyles {
    static let all: [CatStyle] = [
        CatStyle(id: "classic",  name: "Classic",  glyph: "🐱"),
        CatStyle(id: "tabby",    name: "Tabby",    glyph: "🐈"),
        CatStyle(id: "void",     name: "Void",     glyph: "🐈‍⬛"),
        CatStyle(id: "smug",     name: "Smug",     glyph: "😼"),
        CatStyle(id: "grin",     name: "Grin",     glyph: "😸"),
        CatStyle(id: "love",     name: "Heart",    glyph: "😻"),
        CatStyle(id: "tiger",    name: "Tiger",    glyph: "🐯"),
        CatStyle(id: "lion",     name: "Lion",     glyph: "🦁"),
        CatStyle(id: "paw",      name: "Paw",      glyph: "🐾"),
    ]

    static func glyph(for id: String) -> String {
        all.first { $0.id == id }?.glyph ?? "🐱"
    }
}
