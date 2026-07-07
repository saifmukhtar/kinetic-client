use thiserror::Error;

#[derive(Error, Debug)]
pub enum ResolverError {
    #[error("Not initialized: call init_light_client() first")]
    NotInitialized,
    
    #[error("You appear to be offline. Cannot connect to the Kinetic network.")]
    Offline,
    
    #[error("Name '{0}' was not found in the Kinetic network. It may be unregistered.")]
    NotFound(String),
    
    #[error("The registration for '{0}' has expired ({1} rounds old).")]
    Expired(String, u64),
    
    #[error("Invalid URL format: {0}")]
    InvalidUrl(String),

    #[error("No 'website' service found in manifest for KID {0}")]
    NoWebsiteService(String),
    
    #[error("Internal error: {0}")]
    Internal(String),
}

#[derive(Error, Debug)]
pub enum DelegationError {
    #[error("Not initialized: call init_light_client() first")]
    NotInitialized,

    #[error("Private key must be exactly 32 bytes")]
    InvalidPrivateKey,

    #[error("Name '{0}' contains invalid characters")]
    InvalidName(String),

    #[error("Name must be at least 8 characters long")]
    NameTooShort,

    #[error("Failed to fetch drand randomness from all endpoints")]
    DrandFetchFailed,

    #[error("VDF proof invalid or rejected: {0}")]
    InvalidProof(String),

    #[error("VDF proof string exceeds maximum allowed length")]
    ProofTooLong,

    #[error("Internal error: {0}")]
    Internal(String),
}

#[derive(Error, Debug)]
pub enum DaemonError {
    #[error("Network client already initialized")]
    AlreadyInitialized,

    #[error("Not initialized: call init_light_client() first")]
    NotInitialized,

    #[error("Invalid app directory provided")]
    InvalidAppDirectory,

    #[error("Failed to start proxy server: {0}")]
    ProxyStartFailed(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

#[derive(Error, Debug)]
pub enum IdentityError {
    #[error("Not initialized: call init_light_client() first")]
    NotInitialized,

    #[error("You appear to be offline. Cannot connect to the Kinetic network.")]
    Offline,

    #[error("Identity '{0}' was not found in the Kinetic network.")]
    NotFound(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_formatting() {
        let err = ResolverError::NotFound("test".to_string());
        assert_eq!(err.to_string(), "Name 'test' was not found in the Kinetic network. It may be unregistered.");

        let err = DelegationError::NameTooShort;
        assert_eq!(err.to_string(), "Name must be at least 8 characters long");

        let err = DaemonError::AlreadyInitialized;
        assert_eq!(err.to_string(), "Network client already initialized");

        let err = IdentityError::Offline;
        assert_eq!(err.to_string(), "You appear to be offline. Cannot connect to the Kinetic network.");
    }
}
