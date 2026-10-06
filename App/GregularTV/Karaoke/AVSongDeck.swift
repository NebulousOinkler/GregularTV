import AVFoundation
import GregularScreens
import UniformTypeIdentifiers

/// `SongDeck` on Apple TV: each song fetched whole into memory through the
/// app's own network path (`SpecialModeSession.download`, by the same rules
/// as every other request), then played by an `AVPlayer` straight from
/// memory (`MemoryLoader`), never from disk. Shown by `VideoSurface`.
@MainActor final class AVSongDeck: SongDeck {
    let player = AVPlayer()
    var onFinish: (() -> Void)?
    private let download: (URL, Int) async throws -> Data
    /// The song on: the resource loader holds it only weakly.
    private var loader: MemoryLoader?
    private var finished: NSObjectProtocol?

    init(download: @escaping (URL, Int) async throws -> Data) {
        self.download = download
        player.actionAtItemEnd = .pause
    }

    func load(_ url: URL, mostBytes: Int) async throws -> any SongFile {
        MemorySong(data: try await download(url, mostBytes), fileExtension: url.pathExtension)
    }

    func cue(_ file: any SongFile) {
        guard let song = file as? MemorySong else { return }
        clear()
        let loader = MemoryLoader(data: song.data, contentType: song.contentType)
        // A made-up scheme, so AVFoundation asks the loader rather than the network.
        let asset = AVURLAsset(url: URL(string: "gregular-song://song")!)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        self.loader = loader
        let item = AVPlayerItem(asset: asset)
        finished = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFinish?() }
        }
        player.replaceCurrentItem(with: item)
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func restart() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func clear() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let finished { NotificationCenter.default.removeObserver(finished) }
        finished = nil
        loader = nil
    }

    var position: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }
}

/// A song held in memory.
@MainActor final class MemorySong: SongFile {
    let data: Data
    /// Its kind, for AVFoundation, from the file's extension ("m4a", "mp4"…).
    let contentType: String

    init(data: Data, fileExtension: String) {
        self.data = data
        contentType = UTType(filenameExtension: fileExtension)?.identifier ?? UTType.mpeg4Movie.identifier
    }
}

/// Answers AVFoundation's requests for a song from the bytes in memory.
final class MemoryLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    let queue = DispatchQueue(label: "tv.gregular.karaoke-song")
    private let data: Data
    private let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        if let information = request.contentInformationRequest {
            information.contentType = contentType
            information.contentLength = Int64(data.count)
            information.isByteRangeAccessSupported = true
        }
        if let wanted = request.dataRequest {
            let start = min(Int(wanted.requestedOffset), data.count)
            let end = wanted.requestsAllDataToEndOfResource ? data.count : min(data.count, start + wanted.requestedLength)
            wanted.respond(with: data.subdata(in: start..<end))
        }
        request.finishLoading()
        return true
    }
}
