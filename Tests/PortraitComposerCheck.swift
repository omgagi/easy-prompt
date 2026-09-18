import AVFoundation
import Foundation

@main
struct PortraitComposerCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Expected an input movie and output folder")
        }
        let source = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let folder = URL(fileURLWithPath: CommandLine.arguments[2])
        let portraitURL = folder.appendingPathComponent("easy-prompt-portrait-input.mov")
        let mergedURL = folder.appendingPathComponent("easy-prompt-portrait-joined.mov")
        try? FileManager.default.removeItem(at: portraitURL)
        try? FileManager.default.removeItem(at: mergedURL)

        let sourceVideo = try await source.loadTracks(withMediaType: .video).first!
        let size = try await sourceVideo.load(.naturalSize)
        let duration = try await source.load(.duration)
        let composition = AVMutableComposition()
        try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                              of: source, at: .zero)
        // A nonidentity portrait matrix catches exporters that discard track orientation.
        let portraitTransform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1,
                                                  tx: size.width, ty: size.height)
        composition.tracks(withMediaType: .video).forEach { $0.preferredTransform = portraitTransform }
        let fixtureExport = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await fixtureExport.export(to: portraitURL, as: .mov)

        try await SegmentComposer.merge([portraitURL, portraitURL], into: mergedURL)
        let merged = AVURLAsset(url: mergedURL)
        let track = try await merged.loadTracks(withMediaType: .video).first!
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: try await track.load(.naturalSize))
            .applying(transform).standardized
        let mergedDuration = try await merged.load(.duration)
        let fixtureTrack = try await AVURLAsset(url: portraitURL).loadTracks(withMediaType: .video).first!
        let fixtureTransform = try await fixtureTrack.load(.preferredTransform)
        print("Fixture transform: \(fixtureTransform), merged transform: \(transform), bounds: \(bounds)")
        fflush(stdout)
        precondition(transform == portraitTransform, "Portrait rotation was lost")
        precondition(bounds.height > bounds.width, "Final video is not portrait")
        precondition(abs(mergedDuration.seconds - 2 * duration.seconds) < 0.25,
                     "Merged duration is incorrect")
        print("PortraitComposer: output keeps vertical orientation and both takes")
    }
}
