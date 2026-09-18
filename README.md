# Easy Prompt

Easy Prompt is an iPhone teleprompter with a live front-camera preview. The script follows recognized English or Spanish speech and highlights the current word in yellow. The interface is in English.

## Run on iPhone

1. Open `TeleprompterVoz.xcodeproj` in Xcode and select your iPhone.
2. Build and run. Allow camera, microphone, and Speech Recognition access.
3. Tap the script box to open the plain white editor. Tap where you want to type, or press and hold to use the normal iOS **Paste** menu. Tap **Done** to return to the camera.
4. Tap the red button to record. Tap it again to pause, then tap it to resume. The red progress bar fills in 2½-minute sections, with no timer labels. It stops during pauses and goes back when you undo a take. Status, **Mic OK**, and **Voice OK** appear below the record button.
5. While paused, tap **Undo** to discard the last take and return the script to its starting word. Tap the checkmark to join the remaining takes into one video. The video is saved to Photos when permission is granted; tap **Share** to send it elsewhere.

The script is visible only in the camera preview and is not embedded in the video. Recognition detects English or Spanish from the script. Depending on device support and availability, iOS may use Apple's speech recognition service. The installed name is **Easy Prompt**; the bundle identifier is kept so this build updates the previous installation.

The clip controls are in development for version 1.1. Version 1.0, build 2, remains the submitted App Store build.

## Verification

The project builds for iPhone. The script follower has checks for progress, repeated partial results, short skips, off-script pauses, manual repositioning, accents, and punctuation. Run them with:

```sh
swiftc -module-cache-path /private/tmp/teleprompter-swift-cache TeleprompterVoz/ScriptFollower.swift Tests/ScriptFollowerCheck.swift -o /private/tmp/ScriptFollowerCheck
/private/tmp/ScriptFollowerCheck
```

`Tests/SegmentComposerCheck.swift` verifies that two recorded movie files can be joined into one playable video with the expected duration.
