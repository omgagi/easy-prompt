import AVFoundation

enum SegmentComposer {
    static func merge(_ urls: [URL], into outputURL: URL) async throws {
        let composition = AVMutableComposition()
        var orientation = CGAffineTransform.identity
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isValid && duration > .zero else { continue }
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else { continue }
            if cursor == .zero { orientation = try await sourceVideo.load(.preferredTransform) }
            try await composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: asset, at: cursor
            )
            cursor = cursor + duration
        }
        composition.tracks(withMediaType: .video).forEach { $0.preferredTransform = orientation }
        guard cursor > .zero,
              let exporter = AVAssetExportSession(
                asset: composition, presetName: AVAssetExportPresetPassthrough
              ) else {
            throw NSError(domain: "EasyPrompt", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No video to save."])
        }
        try await exporter.export(to: outputURL, as: .mov)
    }
}
