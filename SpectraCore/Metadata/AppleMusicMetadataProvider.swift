import Foundation

public final class AppleMusicMetadataProvider: MediaMetadataProvider {
    public init() {}

    public func currentMetadata() async -> MediaMetadata? {
        let source = """
        if application "Music" is running then
            tell application "Music"
                if player state is playing then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    return trackName & linefeed & trackArtist & linefeed & trackAlbum
                end if
            end tell
        end if
        return ""
        """

        return await Task.detached(priority: .utility) {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return nil }
            let descriptor = script.executeAndReturnError(&error)
            guard error == nil else { return nil }
            let value = descriptor.stringValue ?? ""
            let parts = value
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard let title = parts.first, !title.isEmpty else { return nil }
            return MediaMetadata(
                currentTrackTitle: title,
                artist: parts.dropFirst().first,
                album: parts.dropFirst(2).first,
                artworkData: nil,
                sourceApp: "Apple Music",
                isPlaying: true
            )
        }.value
    }
}
