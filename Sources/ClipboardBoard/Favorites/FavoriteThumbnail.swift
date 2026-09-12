import AppKit
import ClipboardCore

/// Store a bounded list thumbnail with the record; original bytes stay intact.
enum FavoriteThumbnail {
    static func make(for payload: ClipPayload) -> Data? {
        guard case .image(let data) = payload, let image = NSImage(data:data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1,min(180/image.size.width,120/image.size.height))
        let size = NSSize(width:max(1,image.size.width*scale),height:max(1,image.size.height*scale))
        let thumbnail = NSImage(size:size)
        thumbnail.lockFocus()
        image.draw(in:NSRect(origin:.zero,size:size))
        thumbnail.unlockFocus()
        guard let tiff = thumbnail.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff) else { return nil }
        return bitmap.representation(using:.png,properties:[:])
    }
}
