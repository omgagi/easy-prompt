# Easy Prompt

Easy Prompt is an iPhone teleprompter with a live front-camera preview. The script follows recognized English or Spanish speech and highlights the current word in yellow. The interface is in English.

## Run on iPhone

1. Open `TeleprompterVoz.xcodeproj` in Xcode and select your iPhone.
2. Build and run. Allow camera, microphone, and Speech Recognition access.
3. Tap the script box to open the plain white editor. Tap where you want to type, or press and hold to use the normal iOS **Paste** menu. Tap **Done** to return to the camera.
4. Tap **Record** on the main screen. Read aloud; the highlighted word and text position follow your speech. **Mic OK** and **Voice OK** show whether audio and speech recognition are active.
5. Tap **Stop**. The video is saved to Photos when permission is granted. Tap **Share** to send it elsewhere.
6. Tap the top-right close button to dismiss the app scene when idle.

The script is visible only in the camera preview and is not embedded in the video. Recognition detects English or Spanish from the script. Depending on device support and availability, iOS may use Apple's speech recognition service. The installed name is **Easy Prompt**; the bundle identifier is kept so this build updates the previous installation.

## Verification

The project builds for iPhone. The script follower has checks for progress, repeated partial results, short skips, off-script pauses, manual repositioning, accents, and punctuation. Run them with:

```sh
swiftc -module-cache-path /private/tmp/teleprompter-swift-cache TeleprompterVoz/ScriptFollower.swift Tests/ScriptFollowerCheck.swift -o /private/tmp/ScriptFollowerCheck
/private/tmp/ScriptFollowerCheck
```
