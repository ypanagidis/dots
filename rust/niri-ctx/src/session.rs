use crate::error::{NiriCtxError, Result};

#[allow(dead_code)]
pub fn attach_native() -> Result<()> {
    Err(NiriCtxError::HerdrUnavailable(
        "native session attach lands after Phase 1; --tmux-role execs bash".to_string(),
    ))
}
