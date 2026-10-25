# KOMEKCI SMS

KOMEKCI SMS is a Flutter app for Android that reads payment SMS messages and sends their transaction details to a server. It processes messages whose sender address ends in `0801`.

## How it works

1. At startup, the app requests SMS and phone permissions and checks for an internet connection.
2. While the app is open, it listens for incoming SMS messages. It also scans the inbox at startup and every minute to recover messages it may have missed.
3. It extracts the amount, transaction time, and sender phone number when present. It also recognizes supported terminal top-up messages.
4. It obtains the receiving phone number from `GET /api/phone` and sends the transaction to `POST /api/transactions`. The request includes the sender, receiver, amount, time, and payment token.
5. It stores transactions and delivery status on the device and filters duplicate SMS messages so an inbox scan does not submit the same payment twice.

Only SMS messages received after the app's first launch are processed. Older messages and old transaction records from previous versions are not resent. Transactions that receive a definite server error are retried during the minute-by-minute scan. Requests with an uncertain outcome, such as a network timeout, are not retried automatically; they can be retried manually from the transaction list.

## Screens

- **SMS list:** Shows the sender, amount, date, and delivery status. The top bar shows sync progress and the countdown to the next scan.
- **Fetch SMS:** Manually scans eligible `0801` messages received since the app's first launch.
- **Payment settings:** Displays the receiver returned by the server and lets the user enter or update the payment token.
- **Error log:** Shows failed requests, response codes, and diagnostic details. The log is stored on the device and can be cleared.

## Requirements and setup

- Flutter `>=3.44.0` and Dart `>=3.13.0 <4.0.0`, as required by the current lockfile
- Android SDK and Java 17
- An Android device that can receive SMS messages and has internet access

```bash
flutter pub get
flutter run
```

On first launch, grant the requested SMS and phone permissions. Open **Payment settings** and save the payment token before processing transactions. No token is included in the source code. SMS listening and periodic inbox scans run while the app is open; there is no persistent background service.

To run the tests:

```bash
flutter test
```

To build an APK:

```bash
flutter build apk --release
```

The current Android release configuration uses a debug signing key. Configure a separate release signing key before distributing the APK.

## Project structure

- `lib/app/home/controllers/home_controller.dart`: SMS parsing, transaction records, duplicate detection, and syncing.
- `lib/app/services/payment_api_service.dart`: Receiver lookup and transaction requests.
- `lib/app/services/payment_token_store.dart`: Locally saved payment token.
- `lib/app/services/transaction_log_store.dart`: Local error log.
- `lib/app/home/views/`: Main screen, payment settings, and error log UI.
- `android/app/src/main/kotlin/com/yaka/smschecker/MainActivity.kt`: Native Android bridge for the SMS inbox, incoming SMS events, and SIM information.

Keep real payment tokens out of commits and rotate any token that has already been shared.
