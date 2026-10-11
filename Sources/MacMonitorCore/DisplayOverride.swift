import Foundation

/// Pure helpers for macOS display override plists under
/// `/Library/Displays/Contents/Resources/Overrides`. Writing the files is done by
/// `HiDPIService` in the app target because it needs administrator privileges.
public enum DisplayOverride {
    public static let overridesPath = "/Library/Displays/Contents/Resources/Overrides"

    public static func hex(_ id: UInt32) -> String {
        String(format: "%x", id)
    }

    public static func folderName(vendorID: UInt32) -> String {
        "DisplayVendorID-\(hex(vendorID))"
    }

    public static func fileName(productID: UInt32) -> String {
        "DisplayProductID-\(hex(productID))"
    }

    public static func fileURL(vendorID: UInt32, productID: UInt32) -> URL {
        URL(fileURLWithPath: overridesPath)
            .appendingPathComponent(folderName(vendorID: vendorID))
            .appendingPathComponent(fileName(productID: productID))
    }

    /// True only for `<overridesPath>/DisplayVendorID-*/DisplayProductID-*`.
    public static func isManagedOverridePath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let directoryURL = url.deletingLastPathComponent()
        return directoryURL.deletingLastPathComponent().path == overridesPath &&
               directoryURL.lastPathComponent.hasPrefix("DisplayVendorID-") &&
               url.lastPathComponent.hasPrefix("DisplayProductID-")
    }

    /// True when `directoryURL` is a `DisplayVendorID-*` folder under `overridesPath`.
    public static func isVendorDirectory(_ directoryURL: URL) -> Bool {
        directoryURL.path.hasPrefix(overridesPath + "/") &&
            directoryURL.lastPathComponent.hasPrefix("DisplayVendorID-")
    }

    /// One `scale-resolutions` entry: big-endian width, height, flags (1), zero.
    public static func scaleResolutionData(width: Int, height: Int) -> Data {
        var data = Data()
        for value in [UInt32(width), UInt32(height), 1, 0] {
            withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    /// XML plist for an override that adds HiDPI (2x pixel) variants of `resolutions`.
    public static func plistData(vendorID: UInt32, productID: UInt32, resolutions: [CustomResolution]) throws -> Data {
        let plistDict: [String: Any] = [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": resolutions.map {
                scaleResolutionData(width: $0.width * 2, height: $0.height * 2)
            }
        ]
        return try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
    }
}
