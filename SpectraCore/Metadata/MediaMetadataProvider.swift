import Foundation

public struct MediaMetadata: Equatable, Sendable {
    public var currentTrackTitle: String?
    public var artist: String?
    public var album: String?
    public var artworkData: Data?
    public var sourceApp: String?
    public var isPlaying: Bool

    public init(
        currentTrackTitle: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artworkData: Data? = nil,
        sourceApp: String? = nil,
        isPlaying: Bool = false
    ) {
        self.currentTrackTitle = currentTrackTitle
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.sourceApp = sourceApp
        self.isPlaying = isPlaying
    }
}

public protocol MediaMetadataProvider {
    func currentMetadata() async -> MediaMetadata?
}
