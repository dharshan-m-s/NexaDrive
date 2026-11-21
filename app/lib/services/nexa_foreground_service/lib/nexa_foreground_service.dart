/// Native registration only.
///
/// NexaDrive's Dart API lives in the app's `services/foreground_transfer_service.dart`.
/// This package exists so Flutter registers the transfer MethodChannel on every
/// engine, including the isolated engine WorkManager starts after process death.
library;
