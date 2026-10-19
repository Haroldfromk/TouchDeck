/// 폴더 고르기에서 쓰는 경로. 홈 폴더를 "~"로 줄여 쓰고, 홈 폴더 안에서만 다닌다.
public enum FolderPath {
    public static func abbreviate(_ path: String, home: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    public static func child(_ path: String, _ name: String) -> String {
        path + "/" + name
    }

    /// 한 칸 위. 홈("~")에서는 더 올라가지 않는다
    public static func parent(_ path: String) -> String? {
        guard path != "~", let slash = path.lastIndex(of: "/") else { return nil }
        return String(path[..<slash])
    }

    public static func isInsideHome(_ path: String) -> Bool {
        guard path == "~" || path.hasPrefix("~/") else { return false }
        return !path.split(separator: "/").contains("..")
    }
}
