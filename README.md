# Relay

Relay is a Flutter hackathon app for turning developer context (voice, photos, or text) into structured bug reports, commit/PR summaries, and feature proposals.

## Run it

1. Install Flutter and confirm `flutter doctor` is clean enough to run Android or iOS.
2. Fetch packages: `flutter pub get`.
3. Run with a real Groq key: `flutter run --dart-define=GROQ_API_KEY=your_key_here`.

Android/iOS project files and required camera, microphone, and speech-recognition permissions are already included.

Without a key, the app shows a fully structured mock artifact, so the capture-to-output flow remains demonstrable.

## Test each milestone

1. **Model and navigation:** type any bug description, choose Bug, and tap **Type Text & Create**. You should see the processing state, then an output with labelled fields.
2. **Voice:** choose an artifact type, tap **Record Voice**, grant permissions, speak, then tap **Stop & process voice**. The recognized transcript is sent into the same flow.
3. **AI:** launch with `GROQ_API_KEY`; submit text and verify the fields are AI-generated and match the selected template.
4. **Camera + OCR:** tap **Take Photo**, photograph an error or a whiteboard, and confirm extracted text generates the selected artifact type.
5. **Export:** in the output screen, tap **Copy formatted output**, then paste into any text field.

Run the unit test with `flutter test`.
