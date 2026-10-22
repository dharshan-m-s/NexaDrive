use std::{
    collections::VecDeque,
    ffi::CString,
    path::Path,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::SqlitePool;
use tracing::warn;

/// Number of samples retained for charts. At one sample every 5s this is one
/// hour of recent history. History is in-memory only and resets on restart.
pub(crate) const MAX_SAMPLES: usize = 720;

/// One point in the metrics time series, pushed by the background sampler.
#[derive(Clone, Serialize)]
pub(crate) struct MetricSample {
    pub(crate) at: DateTime<Utc>,
    /// Requests observed during the interval since the previous sample.
    pub(crate) requests: u64,
    pub(crate) errors: u64,
    /// Mean response time over the interval, milliseconds.
    pub(crate) latency_ms: Option<f64>,
    /// Whole-machine CPU utilisation, percent.
    pub(crate) cpu_percent: Option<f64>,
    pub(crate) mem_used_mb: Option<f64>,
    pub(crate) mem_total_mb: Option<f64>,
    /// CPU/memory attributable to the NexaDrive server process only.
    pub(crate) server_cpu_percent: Option<f64>,
    pub(crate) server_mem_mb: Option<f64>,
    pub(crate) disk_free_gb: Option<f64>,
    pub(crate) disk_total_gb: Option<f64>,
}

/// Result of a `PRAGMA quick_check`, cached between runs.
#[derive(Clone, Serialize)]
pub(crate) struct DbCheck {
    pub(crate) ok: bool,
    pub(crate) detail: String,
    pub(crate) size_bytes: u64,
    pub(crate) at: DateTime<Utc>,
}

#[derive(Clone, Copy)]
struct CpuTimes {
    total: u64,
    idle: u64,
}

struct MetricsState {
    prev_cpu: Option<CpuTimes>,
    prev_proc_ticks: Option<u64>,
    prev_at: Option<Instant>,
    prev_requests: u64,
    prev_errors: u64,
    prev_latency_micros: u64,
    samples: VecDeque<MetricSample>,
    last_db_check: Option<DbCheck>,
    last_db_check_at: Option<Instant>,
}

/// Process-wide observability counters plus a bounded in-memory time series.
pub(crate) struct Metrics {
    requests_total: AtomicU64,
    errors_total: AtomicU64,
    latency_micros_total: AtomicU64,
    state: Mutex<MetricsState>,
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new()
    }
}

impl Metrics {
    pub(crate) fn new() -> Self {
        Self {
            requests_total: AtomicU64::new(0),
            errors_total: AtomicU64::new(0),
            latency_micros_total: AtomicU64::new(0),
            state: Mutex::new(MetricsState {
                prev_cpu: None,
                prev_proc_ticks: None,
                prev_at: None,
                prev_requests: 0,
                prev_errors: 0,
                prev_latency_micros: 0,
                samples: VecDeque::with_capacity(MAX_SAMPLES),
                last_db_check: None,
                last_db_check_at: None,
            }),
        }
    }

    /// Record one completed request. `status` is the HTTP status code.
    pub(crate) fn record(&self, status: u16, latency: Duration) {
        self.requests_total.fetch_add(1, Ordering::Relaxed);
        self.latency_micros_total
            .fetch_add(latency.as_micros() as u64, Ordering::Relaxed);
        if status >= 500 {
            self.errors_total.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub(crate) fn totals(&self) -> (u64, u64, f64) {
        let req = self.requests_total.load(Ordering::Relaxed);
        let err = self.errors_total.load(Ordering::Relaxed);
        let micros = self.latency_micros_total.load(Ordering::Relaxed);
        let avg_ms = if req > 0 {
            micros as f64 / req as f64 / 1000.0
        } else {
            0.0
        };
        (req, err, avg_ms)
    }

    pub(crate) fn samples(&self) -> Vec<MetricSample> {
        match self.state.lock() {
            Ok(s) => s.samples.iter().cloned().collect(),
            Err(_) => Vec::new(),
        }
    }

    pub(crate) fn last_db_check(&self) -> Option<DbCheck> {
        self.state.lock().ok().and_then(|s| s.last_db_check.clone())
    }

    /// Run a `PRAGMA quick_check` and cache the result. `force` re-runs even if
    /// a recent result is cached. This is read-only and never mutates the DB.
    pub(crate) async fn check_db(&self, db: &SqlitePool, db_path: &str, force: bool) -> DbCheck {
        let size = db_size_bytes(db_path);
        {
            if let Ok(s) = self.state.lock()
                && !force
                && let (Some(check), Some(at)) = (&s.last_db_check, s.last_db_check_at)
                && at.elapsed() < Duration::from_secs(300)
            {
                return check.clone();
            }
        }
        let detail = match sqlx::query_scalar::<_, String>("PRAGMA quick_check")
            .fetch_all(db)
            .await
        {
            Ok(rows) if rows.iter().all(|r| r.eq_ignore_ascii_case("ok")) => "ok".to_string(),
            Ok(rows) => rows.join("; "),
            Err(_) => "check failed to run".to_string(),
        };
        let check = DbCheck {
            ok: detail.eq_ignore_ascii_case("ok"),
            detail,
            size_bytes: size,
            at: Utc::now(),
        };
        if let Ok(mut s) = self.state.lock() {
            s.last_db_check = Some(check.clone());
            s.last_db_check_at = Some(Instant::now());
        }
        check
    }

    /// Compute and store one sample. Called by the background sampler.
    pub(crate) fn tick(&self, storage_root: &Path) {
        let Ok(mut s) = self.state.lock() else {
            return;
        };
        let now = Instant::now();
        let elapsed = s.prev_at.map(|p| now.duration_since(p)).unwrap_or_default();
        if elapsed.as_secs_f64() < 0.5 {
            return;
        }

        let cpu = read_system_cpu().ok();
        let cpu_percent = match (s.prev_cpu, cpu) {
            (Some(prev), Some(cur)) if cur.total > prev.total => {
                let total = (cur.total - prev.total) as f64;
                let idle = cur.idle.saturating_sub(prev.idle) as f64;
                Some(((total - idle) / total * 100.0).clamp(0.0, 100.0))
            }
            _ => None,
        };
        s.prev_cpu = cpu;

        let proc_ticks = read_proc_cpu_ticks().ok();
        let server_cpu_percent = match (s.prev_proc_ticks, proc_ticks, elapsed.as_secs_f64()) {
            (Some(prev), Some(cur), secs) if secs > 0.0 && cur >= prev => {
                let ticks = (cur - prev) as f64;
                Some((ticks / clk_tck() / secs * 100.0).clamp(0.0, 100.0 * num_cpus() as f64))
            }
            _ => None,
        };
        s.prev_proc_ticks = proc_ticks;

        let mem = read_meminfo().ok();
        let server_mem_mb = read_proc_rss_bytes().ok().map(|b| b as f64 / 1_048_576.0);
        let disk = read_disk(storage_root).ok();

        let requests_total = self.requests_total.load(Ordering::Relaxed);
        let errors_total = self.errors_total.load(Ordering::Relaxed);
        let latency_micros = self.latency_micros_total.load(Ordering::Relaxed);
        let req_delta = requests_total.saturating_sub(s.prev_requests);
        let err_delta = errors_total.saturating_sub(s.prev_errors);
        let lat_delta = latency_micros.saturating_sub(s.prev_latency_micros);
        let latency_ms = if req_delta > 0 {
            Some(lat_delta as f64 / req_delta as f64 / 1000.0)
        } else {
            None
        };

        let sample = MetricSample {
            at: Utc::now(),
            requests: req_delta,
            errors: err_delta,
            latency_ms,
            cpu_percent,
            mem_used_mb: mem.map(|m| (m.0 - m.1) as f64 / 1024.0),
            mem_total_mb: mem.map(|m| m.0 as f64 / 1024.0),
            server_cpu_percent,
            server_mem_mb,
            disk_free_gb: disk.map(|d| d.1 as f64 / 1_073_741_824.0),
            disk_total_gb: disk.map(|d| d.0 as f64 / 1_073_741_824.0),
        };

        s.prev_requests = requests_total;
        s.prev_errors = errors_total;
        s.prev_latency_micros = latency_micros;
        s.prev_at = Some(now);

        if s.samples.len() >= MAX_SAMPLES {
            s.samples.pop_front();
        }
        s.samples.push_back(sample);
    }
}

/// Spawns the periodic sampler. Runs until the process exits.
pub(crate) fn spawn_sampler(
    metrics: Arc<Metrics>,
    db: SqlitePool,
    storage_root: std::path::PathBuf,
    db_path: String,
) {
    tokio::spawn(async move {
        let mut db_counter = 0u32;
        loop {
            metrics.tick(&storage_root);
            // Refresh the cached DB integrity result roughly every 10 minutes.
            if db_counter.is_multiple_of(120) {
                let check = metrics.check_db(&db, &db_path, false).await;
                if !check.ok {
                    warn!(detail = %check.detail, "database quick_check reported a problem");
                }
            }
            db_counter = db_counter.wrapping_add(1);
            tokio::time::sleep(Duration::from_secs(5)).await;
        }
    });
}

// --------------------------------------------------------------- /proc readers

fn num_cpus() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1)
}

fn clk_tck() -> f64 {
    unsafe {
        let v = libc::sysconf(libc::_SC_CLK_TCK);
        if v > 0 { v as f64 } else { 100.0 }
    }
}

fn read_system_cpu() -> Result<CpuTimes, std::io::Error> {
    let content = std::fs::read_to_string("/proc/stat")?;
    let line = content
        .lines()
        .find(|l| l.starts_with("cpu "))
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, "no cpu line"))?;
    let nums: Vec<u64> = line
        .split_whitespace()
        .skip(1)
        .filter_map(|v| v.parse::<u64>().ok())
        .collect();
    if nums.len() < 5 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "cpu line short",
        ));
    }
    let idle = nums[3] + nums[4];
    let total: u64 = nums.iter().sum();
    Ok(CpuTimes { total, idle })
}

/// utime + stime for this process, in clock ticks.
fn read_proc_cpu_ticks() -> Result<u64, std::io::Error> {
    let content = std::fs::read_to_string("/proc/self/stat")?;
    let after_comm = content
        .rfind(')')
        .map(|i| &content[i + 1..])
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "bad stat"))?;
    let fields: Vec<&str> = after_comm.split_whitespace().collect();
    // After the ')': state is field 3, so utime(14) = index 11, stime(15) = 12.
    let utime: u64 = fields
        .get(11)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "no utime"))?;
    let stime: u64 = fields
        .get(12)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "no stime"))?;
    Ok(utime + stime)
}

fn read_proc_rss_bytes() -> Result<u64, std::io::Error> {
    let content = std::fs::read_to_string("/proc/self/statm")?;
    let pages: u64 = content
        .split_whitespace()
        .nth(1)
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidData, "no rss"))?;
    let page_size = unsafe {
        let v = libc::sysconf(libc::_SC_PAGESIZE);
        if v > 0 { v as u64 } else { 4096 }
    };
    Ok(pages * page_size)
}

/// (total_kb, available_kb)
pub(crate) fn read_meminfo() -> Result<(u64, u64), std::io::Error> {
    let content = std::fs::read_to_string("/proc/meminfo")?;
    let mut total = None;
    let mut available = None;
    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            total = rest.split_whitespace().next().and_then(|v| v.parse().ok());
        } else if let Some(rest) = line.strip_prefix("MemAvailable:") {
            available = rest.split_whitespace().next().and_then(|v| v.parse().ok());
        }
        if total.is_some() && available.is_some() {
            break;
        }
    }
    match (total, available) {
        (Some(t), Some(a)) => Ok((t, a)),
        _ => Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "meminfo short",
        )),
    }
}

pub(crate) fn read_loadavg() -> Option<(f64, f64, f64)> {
    let content = std::fs::read_to_string("/proc/loadavg").ok()?;
    let mut it = content.split_whitespace();
    let one = it.next()?.parse().ok()?;
    let five = it.next()?.parse().ok()?;
    let fifteen = it.next()?.parse().ok()?;
    Some((one, five, fifteen))
}

/// (total_bytes, available_bytes) for the filesystem containing `path`.
pub(crate) fn read_disk(path: &Path) -> Result<(u64, u64), std::io::Error> {
    let c = CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::InvalidInput, "bad path"))?;
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    let rc = unsafe { libc::statvfs(c.as_ptr(), &mut st) };
    if rc != 0 {
        return Err(std::io::Error::last_os_error());
    }
    let frsize = st.f_frsize as u64;
    let total = (st.f_blocks as u64).saturating_mul(frsize);
    let available = (st.f_bavail as u64).saturating_mul(frsize);
    Ok((total, available))
}

/// Filesystem type backing `path`, by matching the longest `/proc/mounts`
/// prefix. Used to name the actual `/mnt/data3` filesystem honestly.
pub(crate) fn mount_info(path: &Path) -> Option<(String, String)> {
    let canonical = path.canonicalize().ok()?;
    let content = std::fs::read_to_string("/proc/mounts").ok()?;
    let mut best: Option<(usize, String, String)> = None;
    for line in content.lines() {
        let mut parts = line.split_whitespace();
        let _source = parts.next()?;
        let mount = parts.next()?;
        let fstype = parts.next()?;
        let mount_path = Path::new(mount);
        if canonical.starts_with(mount_path) {
            let len = mount_path.as_os_str().len();
            if best.as_ref().map(|(l, _, _)| len > *l).unwrap_or(true) {
                best = Some((len, mount.to_string(), fstype.to_string()));
            }
        }
    }
    best.map(|(_, m, f)| (m, f))
}

/// Size of the SQLite database file plus its WAL/SHM sidecars.
pub(crate) fn db_size_bytes(db_path: &str) -> u64 {
    let mut total = 0;
    for suffix in ["", "-wal", "-shm"] {
        if let Ok(meta) = std::fs::metadata(format!("{db_path}{suffix}")) {
            total += meta.len();
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counters_start_at_zero() {
        let m = Metrics::new();
        assert_eq!(m.totals(), (0, 0, 0.0));
    }

    #[test]
    fn records_requests_and_errors() {
        let m = Metrics::new();
        m.record(200, Duration::from_millis(10));
        m.record(500, Duration::from_millis(30));
        let (req, err, avg) = m.totals();
        assert_eq!(req, 2);
        assert_eq!(err, 1);
        assert!((avg - 20.0).abs() < 0.001);
    }

    #[test]
    fn reads_own_process_and_system_metrics() {
        assert!(read_system_cpu().is_ok());
        assert!(read_proc_cpu_ticks().is_ok());
        assert!(read_proc_rss_bytes().unwrap() > 0);
        let (total, avail) = read_meminfo().unwrap();
        assert!(total > 0 && avail <= total);
    }

    #[test]
    fn disk_reading_works_for_tmp() {
        let (total, avail) = read_disk(Path::new("/tmp")).unwrap();
        assert!(total > 0);
        assert!(avail <= total);
    }

    #[test]
    fn db_size_is_at_least_zero() {
        assert_eq!(db_size_bytes("/path/that/does/not/exist.db"), 0);
    }
}
