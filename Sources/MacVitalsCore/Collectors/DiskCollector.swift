import Darwin

enum DiskCollector {
    /// On APFS the user's files live on the Data volume; `/` is the sealed system snapshot.
    static func snapshot() -> DiskSnapshot {
        for path in ["/System/Volumes/Data", "/"] {
            var fs = statfs()
            if statfs(path, &fs) == 0 {
                let block = UInt64(fs.f_bsize)
                return DiskSnapshot(totalBytes: UInt64(fs.f_blocks) * block, availableBytes: UInt64(fs.f_bavail) * block)
            }
        }
        return DiskSnapshot(totalBytes: 0, availableBytes: 0)
    }
}
