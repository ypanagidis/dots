use crate::error::{NiriCtxError, Result};
use crate::planner::Effect;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExecutorMode {
    Phase1Live,
    DryRun,
}

pub struct Executor {
    mode: ExecutorMode,
}

impl Executor {
    pub fn new(mode: ExecutorMode) -> Self {
        Self { mode }
    }

    pub fn run(&self, effects: &[Effect]) -> Result<()> {
        match self.mode {
            ExecutorMode::DryRun => {
                for effect in effects {
                    println!("{effect:?}");
                }
                Ok(())
            }
            ExecutorMode::Phase1Live => {
                for effect in effects {
                    match effect {
                        Effect::Log { level, msg } => tracing::info!(%level, %msg),
                        Effect::Fail { diag } => return Err(NiriCtxError::Config(diag.clone())),
                        other if other.is_mutating() => {
                            return Err(NiriCtxError::ReadOnlyEffect(Box::new(other.clone())));
                        }
                        _ => {}
                    }
                }
                Ok(())
            }
        }
    }
}
