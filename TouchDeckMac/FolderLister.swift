import Foundation

/// 폴더 고르기용 하위 폴더 목록. 숨김 폴더와 앱(.app 같은 패키지), 파일은 뺀다.
enum FolderLister {
    static func children(atPath path: String) -> [String]? {
        let url = URL(filePath: path)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return nil }
        return urls
            .filter { item in
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                return values?.isDirectory == true && values?.isPackage != true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
