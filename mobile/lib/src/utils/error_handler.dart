import 'package:kinetic/src/rust/api/error.dart';

/// Parses errors thrown by the flutter_rust_bridge FFI layer and converts them 
/// into user-friendly strings matching the domain-specific error messages defined in Rust.
String parseKineticError(dynamic error) {
  if (error is ResolverError) {
    return error.when(
      notInitialized: () => "Not initialized: call init_light_client() first",
      offline: () => "You appear to be offline. Cannot connect to the Kinetic network.",
      notFound: (name) => "Name '$name' was not found in the Kinetic network. It may be unregistered.",
      expired: (name, rounds) => "The registration for '$name' has expired ($rounds rounds old).",
      invalidUrl: (url) => "Invalid URL format: $url",
      noWebsiteService: (kid) => "No 'website' service found in manifest for KID $kid",
      internal: (msg) => "Internal error: $msg",
    );
  } else if (error is DelegationError) {
    return error.when(
      notInitialized: () => "Not initialized: call init_light_client() first",
      invalidPrivateKey: () => "Private key must be exactly 32 bytes",
      invalidName: (name) => "Name '$name' contains invalid characters",
      nameTooShort: () => "Name must be at least 8 characters long",
      drandFetchFailed: () => "Failed to fetch drand randomness from all endpoints",
      invalidProof: (msg) => "VDF proof invalid or rejected: $msg",
      proofTooLong: () => "VDF proof string exceeds maximum allowed length",
      internal: (msg) => "Internal error: $msg",
    );
  } else if (error is DaemonError) {
    return error.when(
      alreadyInitialized: () => "Network client already initialized",
      notInitialized: () => "Not initialized: call init_light_client() first",
      invalidAppDirectory: () => "Invalid app directory provided",
      proxyStartFailed: (msg) => "Failed to start proxy server: $msg",
      internal: (msg) => "Internal error: $msg",
    );
  } else if (error is IdentityError) {
    return error.when(
      notInitialized: () => "Not initialized: call init_light_client() first",
      offline: () => "You appear to be offline. Cannot connect to the Kinetic network.",
      notFound: (name) => "Identity '$name' was not found in the Kinetic network.",
      internal: (msg) => "Internal error: $msg",
    );
  }

  // Fallback for generic exceptions (e.g., AnyhowException, FormatException)
  return error.toString().replaceFirst('Exception: ', '').replaceFirst('AnyhowException(', '').replaceAll(')', '');
}
