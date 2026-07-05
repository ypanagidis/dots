use std::fs;
use std::os::fd::OwnedFd;
use std::path::PathBuf;

use rustix::fs::{flock, open, FlockOperation, Mode, OFlags};

use crate::error::{NiriCtxError, Result};

#[derive(Debug)]
pub enum LockAttempt {
    Acquired(GlobalLock),
    Busy,
}

#[derive(Debug)]
pub struct GlobalLock {
    _fd: OwnedFd,
}

impl GlobalLock {
    pub fn try_acquire() -> Result<LockAttempt> {
        let path = lock_path()?;
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| NiriCtxError::io(parent, source))?;
        }
        let fd = open(
            &path,
            OFlags::CREATE | OFlags::WRONLY | OFlags::CLOEXEC,
            Mode::RUSR | Mode::WUSR | Mode::RGRP | Mode::ROTH,
        )
        .map_err(|source| NiriCtxError::io(&path, std::io::Error::from(source)))?;
        match flock(&fd, FlockOperation::NonBlockingLockExclusive) {
            Ok(()) => Ok(LockAttempt::Acquired(Self { _fd: fd })),
            Err(err) if err == rustix::io::Errno::WOULDBLOCK || err == rustix::io::Errno::AGAIN => {
                Ok(LockAttempt::Busy)
            }
            Err(source) => Err(NiriCtxError::io(&path, std::io::Error::from(source))),
        }
    }
}

fn lock_path() -> Result<PathBuf> {
    if let Some(runtime) = std::env::var_os("XDG_RUNTIME_DIR") {
        return Ok(PathBuf::from(runtime).join("niri-ctx.lock"));
    }
    if let Some(cache) = std::env::var_os("XDG_CACHE_HOME") {
        return Ok(PathBuf::from(cache).join("niri-ctx/niri-ctx.lock"));
    }
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| NiriCtxError::Config("HOME is not set".to_string()))?;
    Ok(home.join(".cache/niri-ctx/niri-ctx.lock"))
}
