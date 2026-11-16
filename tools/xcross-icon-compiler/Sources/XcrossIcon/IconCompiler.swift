import AssetKit
import Foundation

@main
struct IconCompiler {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3 else {
            throw NSError(
                domain: "xcross-icon",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Usage: xcross-icon <Assets.xcassets directory> <AppIcon name> <output directory>"]
            )
        }

        let sourceCatalog = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let iconName = arguments[1]
        let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
        guard !iconName.isEmpty && !iconName.contains("/") && iconName != "." && iconName != ".." else {
            throw NSError(
                domain: "xcross-icon",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid icon set name: \(iconName)"]
            )
        }

        let fm = FileManager.default
        let selected = sourceCatalog.appendingPathComponent("\(iconName).appiconset", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: selected.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(
                domain: "xcross-icon",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Missing icon set: \(selected.path)"]
            )
        }

        let staging = fm.temporaryDirectory
            .appendingPathComponent("xcross-icon-\(UUID().uuidString)", isDirectory: true)
        let catalog = staging.appendingPathComponent("Selected.xcassets", isDirectory: true)
        try fm.createDirectory(at: catalog, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        // Foundation.copyItem can attempt to preserve Linux metadata such as
        // SELinux security xattrs, which is not permitted for unprivileged
        // processes. Stage the icon's regular files by content instead.
        // An .appiconset is flat: Contents.json and the referenced images.
        let stagedIcon = catalog.appendingPathComponent(
            "\(iconName).appiconset", isDirectory: true
        )
        try fm.createDirectory(at: stagedIcon, withIntermediateDirectories: true)
        let iconFiles = try fm.contentsOfDirectory(
            at: selected,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for source in iconFiles {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                throw NSError(
                    domain: "xcross-icon",
                    code: 6,
                    userInfo: [NSLocalizedDescriptionKey:
                        "Unexpected non-file in icon set: \(source.lastPathComponent)"]
                )
            }
            try Data(contentsOf: source).write(
                to: stagedIcon.appendingPathComponent(source.lastPathComponent),
                options: .atomic
            )
        }

        let compiled = try await XCAssetCompiler(deploymentTarget: "16.0")
            .compile(catalog: catalog)
        guard let icon = compiled.appIconBundle, icon.primaryIconName == iconName else {
            throw NSError(
                domain: "xcross-icon",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Selected icon was not compiled"]
            )
        }

        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        try compiled.carData.write(
            to: output.appendingPathComponent("Assets.car"),
            options: .atomic
        )
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: icon.infoPlistAdditions,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: output.appendingPathComponent("IconPlistAdditions.plist"),
            options: .atomic
        )
        for file in icon.looseFiles {
            guard !file.name.contains("/") else {
                throw NSError(
                    domain: "xcross-icon",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid output file: \(file.name)"]
                )
            }
            try file.data.write(
                to: output.appendingPathComponent(file.name),
                options: .atomic
            )
        }

        print("Compiled icon: \(icon.primaryIconName)")
        print("Assets.car: \(compiled.carData.count) bytes")
        print("Loose icon sources: \(icon.looseFiles.count)")
        print("Output: \(output.path)")
    }
}
