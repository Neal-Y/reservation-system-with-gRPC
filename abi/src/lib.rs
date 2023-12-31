mod config;
mod error;
mod pb;
mod types;
mod utils;

pub use config::*;
pub use error::{Error, ReservationConflict, ReservationConflictInfo, ReservationWindow};
pub use pb::*;
pub use types::*;
pub use utils::*;

pub type ReservationId = i64;
pub type ResourceId = String;

pub trait Validator {
    fn validate(&self) -> Result<(), Error>;
}

impl Validator for ReservationId {
    fn validate(&self) -> Result<(), Error> {
        if *self <= 0 {
            return Err(Error::InvalidReservationId(*self));
        }
        Ok(())
    }
}
