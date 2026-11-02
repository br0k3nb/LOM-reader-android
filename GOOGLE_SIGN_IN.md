# Google sign-in setup

The Android app exchanges a native Google ID token with the existing website at `https://lotmreader.vercel.app/api/auth/google`. The server checks the token audience against its configured web OAuth client. The app already uses that deployment's public web client ID:

```text
149159576823-8k9vuolgao75f068vnsj66ufqp1k6f6e.apps.googleusercontent.com
```

## Register this Android build

Open [Google Cloud → Google Auth Platform → Clients](https://console.cloud.google.com/auth/clients) and select the **same project** that owns the web client above. Click **Create client**, select application type **Android**, and register:

| Setting | Value |
| --- | --- |
| Name | `LOTM Reader Android` |
| Package name | `dev.lotm.lotm_reader` |
| SHA-1 of this workspace's signing certificate | `A3:75:AD:78:48:FF:F5:1F:5A:81:84:FC:8C:F6:15:41:1A:03:81:39` |
| SHA-256 of this certificate | `16:60:AE:96:90:03:3B:7C:7C:08:D7:88:F4:7F:86:41:57:D5:5E:6B:65:11:EC:76:17:A6:37:ED:4B:BF:8C:6D` |

Click **Create**. Keep the existing web client unchanged. No Android client ID needs to be pasted into the app, and no Firebase configuration file is required for this integration.

The SHA-1 belongs to the development key used by the release APK built in this workspace; it was verified directly from the APK with `apksigner verify --print-certs`. OAuth client IDs and certificate fingerprints are public identifiers. No client secret is needed in the app. The generated Android client ID does not replace the web client ID passed as `serverClientId`.

This external registration cannot be verified by the local test suite. Google may report a configuration or cancellation error until it is registered, and the app provides email sign-in as an alternative. The existing website's Google authentication endpoint and database must also be enabled, as for its web Google button.

The app displays progress immediately after tapping Google and a visible error when Google cancels or rejects the request. Android Credential Manager can label an OAuth configuration failure as cancellation; the app no longer hides that result. If registration does not resolve it, verify that the selected Cloud project contains the exact web client above and that the APK's signing fingerprint matches the registered Android client. In an OAuth project with an external audience in Testing, the account must be included in **Audience → Test users**.

See the Flutter team's [Google Sign-In Android configuration and troubleshooting](https://pub.dev/packages/google_sign_in_android) and Google's [Android OAuth client registration](https://developers.google.com/identity/sign-in/android/start-integrating#configure_a_google_api_console_project).

## Distribution and other machines

Use a stable distribution keystore and register its signing certificate before distributing APKs. If publishing through Google Play, also register the Play app-signing certificate. Other workstations and fresh CI runners generate different development keys; register their certificates or build with the same distribution key.

This app's Gradle configuration accepts `LOTM_KEYSTORE`, `LOTM_STORE_PASSWORD`, `LOTM_KEY_ALIAS`, and `LOTM_KEY_PASSWORD`. Keep keystores/passwords out of Git. To inspect fingerprints for a configured build, run `./gradlew signingReport` from `android/`, with the appropriate Java SDK and environment variables.

If using another website deployment with a different web client ID, build with:

```sh
flutter build apk --release \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

The ID token is used only for the sign-in exchange. Subsequent authenticated API requests send the website's opaque `lotm_reader_session` cookie from secure storage. Sessions are excluded from exported reading backups and from the chapter WebView.
