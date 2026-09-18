import AVFoundation
import Foundation

@main
struct SegmentComposerCheck {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("Expected two input movies and one output path")
        }
        let first = URL(fileURLWithPath: CommandLine.arguments[1])
        let second = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try? FileManager.default.removeItem(at: output)
        let firstDuration = try await AVURLAsset(url: first).load(.duration).seconds
        let secondDuration = try await AVURLAsset(url: second).load(.duration).seconds
        print("Input durations: \(firstDuration), \(secondDuration)")
        fflush(stdout)
        try await SegmentComposer.merge([first, second], into: output)
        let merged = AVURLAsset(url: output)
        let mergedDuration = try await merged.load(.duration).seconds
        let tracks = try await merged.loadTracks(withMediaType: .video)
        precondition(!tracks.isEmpty, "Merged file has no video track")
        let inputTrack = try await AVURLAsset(url: first).loadTracks(withMediaType: .video).first!
        let inputTransform = try await inputTrack.load(.preferredTransform)
        let outputTransform = try await tracks[0].load(.preferredTransform)
        precondition(inputTransform == outputTransform, "Merged video orientation changed")
        precondition(abs(mergedDuration - firstDuration - secondDuration) < 0.25,
                     "Merged duration does not match the two takes")
        print("SegmentComposer: two takes joined into one playable video")
    }
}
