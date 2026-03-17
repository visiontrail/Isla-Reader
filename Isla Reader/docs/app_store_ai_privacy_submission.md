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

How to verify quickly:
1) Open app launch or Settings > AI Data & Privacy.
2) The consent screen shows data categories, purpose, and third-party recipient identity (provider name + endpoint host) before sharing.
3) Decline blocks AI requests; Allow enables AI requests.

Data sent (only after user consent and user action):
- Selected reading text/chapter excerpts
- User prompt for AI summary/translation/explanation/skimming
- Minimal request metadata needed for response delivery (for example language/model/request ID)

Third-party recipient disclosure:
- Recipient identity is shown in-app before sharing: current third-party AI provider name + endpoint host.
- The same disclosure is available in Settings > AI Data & Privacy.
- Privacy policy also describes AI recipient and handling scope.

Data use and retention:
- Purpose is limited to user-requested AI output generation.
- Uploaded text is not persisted on LanRead server.
- AI outputs remain on device unless user exports them.

Third-party protection:
- We require third-party AI processors to provide confidentiality and security protections equal to or stronger than our policy.

Privacy Policy:
- https://isla-reader.top/privacy
- Policy updated: 2026-03-17
```

## Reply to Rejection Template

```text
Hello App Review Team,

Thank you for the feedback. We have updated the app to comply with Guidelines 5.1.1(i) and 5.1.2(i):

1) Before any AI request is sent, the app now shows an explicit consent screen.
2) The consent screen clearly identifies the third-party AI recipient (provider name + endpoint host) before sharing.
3) The screen explains data categories, purpose of processing, and explicit opt-in requirement.
4) AI requests are blocked until permission is granted.
5) Users can review and change AI data permission anytime in Settings > AI Data & Privacy.
6) Our privacy policy now explicitly describes:
   - what AI-related data is sent,
   - how the data is used,
   - who receives the data (third-party AI recipient),
   - retention scope and user controls,
   - equivalent-or-stronger protection requirements for third-party processors.
7) Updated privacy policy:
   https://isla-reader.top/privacy
   (Updated on 2026-03-17)

Please review build [NEW_BUILD_NUMBER] again. Thank you.
```
