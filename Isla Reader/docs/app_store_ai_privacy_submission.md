# App Store AI Privacy Submission Notes

This checklist and template align with App Store Review Guidelines 5.1.1(i) and 5.1.2(i).

## In-App Behavior Checklist

- The app shows a consent sheet before sending any user-selected reading text to AI.
- The consent sheet discloses:
  - what data is sent (selected text/chapter excerpts/prompts),
  - why it is sent (summary/translation/explanation requested by user),
  - which third-party AI provider receives the data (provider name + endpoint host),
  - explicit opt-in action before any request is sent.
- If consent is not granted, AI requests are blocked.
- Users can review and change consent in `Settings > AI Data & Privacy`.
- The consent sheet includes a direct Privacy Policy link.

## App Review Information (App Store Connect) Template

Use this in **App Store Connect > App Review Information > Notes**:

```text
For AI features, LanRead asks for explicit consent before any AI request is sent.

Data sent (only after user consent and user action):
- Selected reading text/chapter excerpt
- User prompt for AI summary/translation/explanation

Third-party recipient disclosure:
- The consent screen shows the currently configured third-party AI provider name and endpoint host before data sharing.
- This information is also available in Settings > AI Data & Privacy.

User control:
- Users can decline and continue using non-AI reading features.
- AI requests are blocked until consent is granted.
- Users can change consent later in Settings.

Privacy Policy:
- https://isla-reader.top/privacy
```

## Reply to Rejection Template

```text
Hello App Review Team,

Thank you for the feedback. We have updated the app to comply with Guidelines 5.1.1(i) and 5.1.2(i):

1) Before any AI request is sent, the app now shows an explicit consent screen.
2) The consent screen now clearly identifies the third-party AI provider (name + endpoint host) that receives user-selected text/prompts.
3) The screen explains what data is sent and for what purpose.
4) AI requests are blocked until the user grants permission.
5) Users can review and change AI data permission anytime in Settings > AI Data & Privacy.
6) The same data collection/use/sharing details are reflected in our privacy policy:
   https://isla-reader.top/privacy

Please review build 1.0.1 again. Thank you.
```
