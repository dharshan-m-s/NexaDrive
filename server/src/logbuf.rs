use std::{
    collections::VecDeque,
    io::{self, Write},
    sync::{Arc, Mutex},
};

/// Maximum number of recent log lines retained in memory. This is a bounded,
/// ephemeral ring — nothing is written to disk, and it resets when the server
/// restarts. It exists so the localhost console can show the server's own
/// recent output without needing journal access (which the sandboxed service
/// user does not have).
pub(crate) const MAX_LOG_LINES: usize = 500;

/// A single retained line is truncated to keep the ring small.
const MAX_LINE_LEN: usize = 2000;

/// A shared, bounded ring buffer of recent (redacted) log lines.
#[derive(Clone, Default)]
pub(crate) struct LogBuffer {
    inner: Arc<Mutex<VecDeque<String>>>,
}

impl LogBuffer {
    pub(crate) fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(VecDeque::with_capacity(64))),
        }
    }

    pub(crate) fn push(&self, line: &str) {
        let line = redact(line);
        if line.trim().is_empty() {
            return;
        }
        if let Ok(mut guard) = self.inner.lock() {
            if guard.len() >= MAX_LOG_LINES {
                guard.pop_front();
            }
            guard.push_back(line);
        }
    }

    /// Newest-first snapshot, capped to `limit`.
    pub(crate) fn recent(&self, limit: usize) -> Vec<String> {
        let limit = limit.clamp(1, MAX_LOG_LINES);
        match self.inner.lock() {
            Ok(guard) => guard.iter().rev().take(limit).cloned().collect(),
            Err(_) => Vec::new(),
        }
    }
}

/// Best-effort secret redaction for retained log lines.
///
/// The server never intentionally logs credentials, but this is a defensive
/// second line: bearer tokens, and `key=value` pairs whose key looks secret,
/// are masked before a line is stored or served.
pub(crate) fn redact(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut current = String::new();
    for token in input.split_inclusive(char::is_whitespace) {
        let trimmed = token.trim_end();
        let lower = trimmed.to_ascii_lowercase();
        let is_bearer = lower == "bearer" || lower.starts_with("bearer ");
        let is_secret_kv = [
            "token=",
            "password=",
            "passwd=",
            "secret=",
            "authorization=",
            "csrf=",
            "cookie=",
        ]
        .iter()
        .any(|k| lower.starts_with(k) || lower.contains(&format!(" {k}")));
        if is_bearer || is_secret_kv {
            current.push_str("[redacted]");
            // Preserve the trailing whitespace that split_inclusive kept.
            if let Some(ws) = token.strip_prefix(trimmed) {
                current.push_str(ws);
            }
        } else {
            current.push_str(token);
        }
        if current.len() > MAX_LINE_LEN {
            current.truncate(MAX_LINE_LEN);
            out.push_str(&current);
            return out;
        }
    }
    out.push_str(&current);
    if out.len() > MAX_LINE_LEN {
        out.truncate(MAX_LINE_LEN);
    }
    out
}

/// `tracing_subscriber` writer that tees formatted events into a [`LogBuffer`].
#[derive(Clone)]
pub(crate) struct LogMakeWriter {
    buffer: LogBuffer,
}

impl LogMakeWriter {
    pub(crate) fn new(buffer: LogBuffer) -> Self {
        Self { buffer }
    }
}

impl<'a> tracing_subscriber::fmt::MakeWriter<'a> for LogMakeWriter {
    type Writer = LogWriter;

    fn make_writer(&'a self) -> Self::Writer {
        LogWriter {
            buffer: self.buffer.clone(),
            pending: String::new(),
        }
    }
}

pub(crate) struct LogWriter {
    buffer: LogBuffer,
    pending: String,
}

impl LogWriter {
    fn drain_complete_lines(&mut self) {
        while let Some(pos) = self.pending.find('\n') {
            let line: String = self.pending.drain(..=pos).collect();
            self.buffer.push(line.trim_end_matches(['\n', '\r']));
        }
    }
}

impl Write for LogWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        // Tee to stderr so the systemd journal keeps the full record while the
        // console additionally retains a redacted, bounded in-memory copy.
        let _ = io::stderr().write_all(buf);
        self.pending.push_str(&String::from_utf8_lossy(buf));
        self.drain_complete_lines();
        if self.pending.len() > MAX_LINE_LEN * 2 {
            self.buffer.push(&self.pending);
            self.pending.clear();
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        self.drain_complete_lines();
        if !self.pending.is_empty() {
            self.buffer.push(&self.pending);
            self.pending.clear();
        }
        let _ = io::stderr().flush();
        Ok(())
    }
}

impl Drop for LogWriter {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_secrets() {
        assert!(redact("Authorization: Bearer abc123").contains("[redacted]"));
        assert!(redact("password=hunter2").contains("[redacted]"));
        assert!(!redact("password=hunter2").contains("hunter2"));
        assert!(redact("token: deadbeef token=deadbeef").contains("[redacted]"));
        assert_eq!(redact("normal log line"), "normal log line");
    }

    #[test]
    fn ring_buffer_is_bounded_and_newest_first() {
        let buf = LogBuffer::new();
        for i in 0..(MAX_LOG_LINES + 20) {
            buf.push(&format!("line {i}"));
        }
        let recent = buf.recent(MAX_LOG_LINES);
        assert_eq!(recent.len(), MAX_LOG_LINES);
        assert_eq!(recent[0], format!("line {}", MAX_LOG_LINES + 19));
    }

    #[test]
    fn writer_splits_lines() {
        let buf = LogBuffer::new();
        let writer = LogMakeWriter::new(buf.clone());
        {
            use tracing_subscriber::fmt::MakeWriter;
            let mut w = writer.make_writer();
            w.write_all(b"first\nsecond\n").unwrap();
        }
        assert_eq!(buf.recent(10), vec!["second", "first"]);
    }
}
