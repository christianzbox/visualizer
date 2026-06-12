import Foundation

public final class CurrentSourceMetadataProvider: MediaMetadataProvider {
    private let sourceProvider: @Sendable () -> AudioSource?

    public init(sourceProvider: @escaping @Sendable () -> AudioSource?) {
        self.sourceProvider = sourceProvider
    }

    public func currentMetadata() async -> MediaMetadata? {
        guard let source = sourceProvider() else { return nil }
        return MediaMetadata(
            sourceApp: source.name,
            isPlaying: true
        )
    }
}
