//! JSON-lines bridge for the Omarchy shell. Hardware writes belong to batctl.
use serde_json::{json, Value};
use std::{
    env, fs,
    io::{self, BufRead, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc,
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

const MODES: &[&str] = &[
    "full",
    "percentage",
    "icon",
    "watts",
    "runtime",
    "percentage-runtime",
    "profile",
];
const PROFILES: &[&str] = &["power-saver", "balanced", "performance"];
const BEHAVIOURS: &[&str] = &["auto", "inhibit-charge", "force-discharge"];
const PRESETS: &[&str] = &["max-lifespan", "balanced", "plugged-in", "full-charge"];

fn run(program: &str, args: &[&str], seconds: u64) -> Result<String, String> {
    run_input(program, args, seconds, None)
}
fn run_input(
    program: &str,
    args: &[&str],
    seconds: u64,
    input: Option<&str>,
) -> Result<String, String> {
    let mut child = Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("{program}: {e}"))?;
    // Drain both pipes concurrently, including during authentication.
    let stdout = child.stdout.take().unwrap();
    let stderr = child.stderr.take().unwrap();
    let out = thread::spawn(move || io::read_to_string(stdout).unwrap_or_default());
    let err = thread::spawn(move || io::read_to_string(stderr).unwrap_or_default());
    if let Some(input) = input {
        let result = child.stdin.take().unwrap().write_all(input.as_bytes());
        if let Err(error) = result {
            let _ = child.kill();
            let _ = child.wait();
            return Err(format!("{program}: {error}"));
        }
    }
    let start = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if start.elapsed() < Duration::from_secs(seconds) => {
                thread::sleep(Duration::from_millis(40))
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(format!("{program}: operation timed out or was interrupted"));
            }
        }
    };
    let output = out.join().unwrap_or_default();
    let error = err.join().unwrap_or_default();
    if status.success() {
        Ok(output.trim().to_owned())
    } else {
        Err(format!(
            "{program}: {}",
            if error.trim().is_empty() {
                if output.trim().is_empty() {
                    "Operation cancelled or denied"
                } else {
                    output.trim()
                }
            } else {
                error.trim()
            }
        ))
    }
}
fn read(path: impl AsRef<Path>) -> String {
    fs::read_to_string(path)
        .unwrap_or_default()
        .trim()
        .to_owned()
}
fn number(path: impl AsRef<Path>) -> Option<f64> {
    read(path).parse().ok()
}
fn field<'a>(text: &'a str, key: &str) -> Option<&'a str> {
    text.lines()
        .find_map(|line| line.trim().strip_prefix(key).map(str::trim))
}
fn capability(text: &str, key: &str) -> Value {
    let s = field(text, key).unwrap_or("");
    let range = s
        .split("range: ")
        .nth(1)
        .and_then(|x| x.trim_end_matches(')').split_once(".."));
    let values: Vec<u64> = s
        .split("values: [")
        .nth(1)
        .unwrap_or("")
        .split(']')
        .next()
        .unwrap_or("")
        .split_whitespace()
        .filter_map(|n| n.parse().ok())
        .collect();
    json!({"supported": s.starts_with("true"), "min": range.and_then(|r| r.0.parse::<u64>().ok()).unwrap_or(0), "max": range.and_then(|r| r.1.parse::<u64>().ok()).unwrap_or(100), "values": values})
}
fn thresholds(text: &str) -> Value {
    let s = field(text, "Thresholds:").unwrap_or("");
    let n = |key: &str| {
        s.split(key)
            .nth(1)
            .and_then(|x| x.split('%').next())
            .and_then(|x| x.parse::<u64>().ok())
    };
    json!({"start": n("start="), "stop": n("stop=")})
}
// The bracketed token is the active sysfs mode. Never invent unsupported modes.
fn behaviour_state(text: &str) -> Value {
    let available: Vec<&str> = text
        .split_whitespace()
        .map(|s| s.trim_matches(['[', ']']))
        .filter(|s| BEHAVIOURS.contains(s))
        .collect();
    let current = text
        .split_whitespace()
        .find(|s| s.starts_with('[') && s.ends_with(']'))
        .map(|s| s.trim_matches(['[', ']']))
        .filter(|s| BEHAVIOURS.contains(s));
    json!({"current": current, "available": available})
}
fn behaviour_target(root: &Path, args: &[Value]) -> Result<(PathBuf, String), String> {
    let [battery, mode] = args else {
        return Err("Expected a battery and charge behaviour".into());
    };
    let id = battery.as_str().ok_or("Invalid battery")?;
    let mode = mode
        .as_str()
        .filter(|s| BEHAVIOURS.contains(s))
        .ok_or("Invalid charge behaviour")?;
    // Match an actual power-supply entry before constructing a privileged write path.
    let entry = fs::read_dir(root)
        .map_err(|e| e.to_string())?
        .flatten()
        .find(|entry| entry.file_name() == id)
        .ok_or("Battery not found")?;
    let battery = entry.path();
    if read(battery.join("type")) != "Battery"
        || read(battery.join("scope")) == "Device"
        || read(battery.join("present")) == "0"
    {
        return Err("Battery is not available".into());
    }
    let path = battery.join("charge_behaviour");
    let state = behaviour_state(&read(&path));
    if !state["available"]
        .as_array()
        .unwrap()
        .iter()
        .any(|v| v == mode)
    {
        return Err("This charge behaviour is not supported by the battery".into());
    }
    Ok((path, mode.to_owned()))
}
fn battery(path: &Path, status: &str) -> Value {
    let id = path.file_name().unwrap().to_string_lossy();
    let section = status
        .split(&format!("\n{id} ("))
        .nth(1)
        .unwrap_or("")
        .split("\n\n")
        .next()
        .unwrap_or("");
    let n = |name: &str| number(path.join(name));
    let voltage = n("voltage_now").map(|v| v / 1e6);
    let energy = |e: &str, c: &str| {
        n(e).map(|v| v / 1e6)
            .or_else(|| Some(n(c)? / 1e6 * voltage?))
    };
    let now = energy("energy_now", "charge_now");
    let full = energy("energy_full", "charge_full");
    let design = energy("energy_full_design", "charge_full_design");
    let power = n("power_now")
        .map(|v| v.abs() / 1e6)
        .or_else(|| Some(n("current_now")?.abs() / 1e6 * voltage?));
    let state = read(path.join("status"));
    let remaining = if state == "Discharging" {
        now
    } else if state == "Charging" {
        full.zip(now).map(|(f, n)| (f - n).max(0.0))
    } else {
        None
    };
    json!({"id":id,"manufacturer":read(path.join("manufacturer")),"model":read(path.join("model_name")),"status":state,"percent":n("capacity"),"power_w":power,"energy_wh":now,"full_wh":full,"design_wh":design,"health":full.zip(design).filter(|(_,d)|*d>0.0).map(|(f,d)|f/d*100.0),"cycles":n("cycle_count"),"hours":remaining.zip(power).filter(|(_,p)|*p>0.1).map(|(e,p)|e/p),"limits":thresholds(section),"behaviour":behaviour_state(&read(path.join("charge_behaviour"))),"voltage_v":voltage,"temperature_c":n("temp").map(|v|v/10.0)})
}
fn aggregate(batteries: &[Value]) -> Value {
    if batteries.len() == 1 {
        return batteries[0].clone();
    }
    if batteries.is_empty() {
        return Value::Null;
    }
    let sum = |key: &str| -> Option<f64> { batteries.iter().map(|b| b[key].as_f64()).sum() };
    let energy = sum("energy_wh");
    let full = sum("full_wh");
    let signed_power: Option<f64> = batteries
        .iter()
        .map(|b| {
            b["power_w"].as_f64().map(|p| {
                if b["status"] == "Discharging" {
                    -p
                } else if b["status"] == "Charging" {
                    p
                } else {
                    0.0
                }
            })
        })
        .sum();
    let status = match signed_power {
        Some(p) if p > 0.1 => "Charging",
        Some(p) if p < -0.1 => "Discharging",
        _ => "Not charging",
    };
    let remaining = if status == "Discharging" {
        energy
    } else if status == "Charging" {
        full.zip(energy).map(|(f, e)| (f - e).max(0.0))
    } else {
        None
    };
    json!({"id":"__all__","percent":energy.zip(full).filter(|(_,f)|*f>0.0).map(|(e,f)|e/f*100.0),"energy_wh":energy,"full_wh":full,"power_w":signed_power.map(f64::abs),"status":status,"hours":remaining.zip(signed_power).filter(|(_,p)|p.abs()>0.1).map(|(e,p)|e/p.abs())})
}
fn sample(prefs: &Value, root: &Path) -> Value {
    let detect = run("/usr/bin/batctl", &["detect"], 5);
    let status = run("/usr/bin/batctl", &["status"], 5);
    let d = detect.as_deref().unwrap_or("");
    let s = status.as_deref().unwrap_or("");
    let mut batteries = vec![];
    let mut ac = None;
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.flatten() {
            let path = entry.path();
            let kind = read(path.join("type"));
            if kind == "Battery"
                && read(path.join("scope")) != "Device"
                && read(path.join("present")) != "0"
            {
                batteries.push(battery(&path, s));
            } else if kind != "Battery" {
                if let Some(online) = number(path.join("online")) {
                    ac = Some(ac.unwrap_or(false) || online > 0.0);
                }
            }
        }
    }
    batteries.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    let profile = run("powerprofilesctl", &["get"], 5);
    let list = run("powerprofilesctl", &["list"], 5);
    let available: Vec<&str> = list
        .as_deref()
        .unwrap_or("")
        .lines()
        .filter_map(|l| {
            let p = l
                .trim()
                .trim_start_matches('*')
                .trim()
                .trim_end_matches(':');
            PROFILES.iter().find(|&&known| known == p).copied()
        })
        .collect();
    json!({"type":"sample","ts":SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs_f64(),"batteries":batteries,"aggregate":aggregate(&batteries),"ac":ac,"batctl":{"available":detect.is_ok() && status.is_ok(),"backend":field(d,"Backend:"),"start":capability(d,"Start threshold:"),"stop":capability(d,"Stop threshold:"),"boot":s.contains("boot=true"),"resume":s.contains("resume=true"),"error":detect.as_ref().err().or(status.as_ref().err()),"warning":s.lines().filter(|l| l.contains("Warning:") || l.contains("overridden")).collect::<Vec<_>>().join("\n")},"power":{"profile":profile.as_ref().ok(),"profiles":available,"error":profile.err().or(list.err())},"preferences":prefs})
}
fn prefs_path() -> PathBuf {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/state")
        });
    base.join("omarchy-battery-studio/preferences.json")
}
fn valid_preference(key: &str, value: &Value) -> bool {
    match key {
        "display_mode" => value.as_str().is_some_and(|s| MODES.contains(&s)),
        _ => false,
    }
}
fn load_prefs() -> Value {
    let mut prefs = json!({"display_mode":"full"});
    if let Ok(Value::Object(saved)) = serde_json::from_str::<Value>(&read(prefs_path())) {
        for (k, v) in saved {
            if valid_preference(&k, &v) {
                prefs[k] = v;
            }
        }
    }
    prefs
}
fn save_prefs(prefs: &Value) -> Result<(), String> {
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    let path = prefs_path();
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(path.parent().unwrap())
        .map_err(|e| e.to_string())?;
    let temp = path.with_extension(format!("{}.tmp", std::process::id()));
    let result = (|| {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)?;
        file.write_all(prefs.to_string().as_bytes())?;
        file.sync_all()?;
        fs::rename(&temp, &path)
    })();
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result.map_err(|e: io::Error| e.to_string())
}
fn emit(value: &Value) {
    println!("{value}");
    let _ = io::stdout().flush();
}
fn action_args(op: &str, args: &[Value]) -> Result<Vec<String>, String> {
    let strings = |s: &[&str]| s.iter().map(|x| x.to_string()).collect();
    match (op, args) {
        ("preset", [p]) if p.as_str().is_some_and(|p| PRESETS.contains(&p)) => {
            Ok(strings(&["set", "--preset", p.as_str().unwrap()]))
        }
        ("threshold", [start, stop])
            if start.as_u64().is_some_and(|s| s <= 99)
                && stop.as_u64().is_some_and(|e| e > 0 && e <= 100)
                && start.as_u64() < stop.as_u64() =>
        {
            Ok(vec![
                "set".into(),
                "--start".into(),
                start.to_string(),
                "--stop".into(),
                stop.to_string(),
            ])
        }
        ("persist", [v]) if v.is_boolean() => Ok(strings(&[
            "persist",
            if v == true { "enable" } else { "disable" },
        ])),
        ("apply", []) => Ok(strings(&["apply"])),
        _ => Err("Invalid operation or arguments".into()),
    }
}
fn action(request: &Value) -> Result<String, String> {
    let op = request["op"].as_str().unwrap_or("");
    let args = request["args"].as_array().ok_or("Missing arguments")?;
    if op == "behaviour" {
        let (path, mode) = behaviour_target(Path::new("/sys/class/power_supply"), args)?;
        // batctl's backend writes this same sysfs attribute. Its CLI has no setter.
        // A fixed tee executable receives a validated sysfs path and mode via stdin.
        run_input(
            "/usr/bin/pkexec",
            &["/usr/bin/tee", path.to_str().ok_or("Invalid battery path")?],
            120,
            Some(&format!("{mode}\n")),
        )?;
        if behaviour_state(&read(&path))["current"] != mode {
            return Err(
                "The battery did not accept the charge behaviour. Refresh and try again.".into(),
            );
        }
        return Ok(format!("Charge behaviour set to {mode}"));
    }
    if op == "profile" {
        if args.len() != 1 || !args[0].as_str().is_some_and(|p| PROFILES.contains(&p)) {
            return Err("Invalid profile".into());
        }
        // Use Omarchy's own bridge to remember this source's profile as stock panels do.
        return run(
            "omarchy-powerprofiles-set",
            &["autodetect", args[0].as_str().unwrap()],
            15,
        );
    }
    let arguments = action_args(op, args)?;
    let mut refs = vec!["/usr/bin/batctl"];
    refs.extend(arguments.iter().map(String::as_str));
    let output = run("/usr/bin/pkexec", &refs, 120)?;
    if matches!(op, "preset" | "threshold") {
        let status = run("/usr/bin/batctl", &["status"], 5)?;
        if status.contains("boot=true") || status.contains("resume=true") {
            run(
                "/usr/bin/pkexec",
                &["/usr/bin/batctl", "persist", "enable"],
                120,
            )
            .map_err(|e| format!("Limits applied, but saving failed: {e}"))?;
        }
    }
    Ok(output)
}
fn monitor() {
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            match line {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        return;
                    }
                }
                Err(_) => break,
            }
        }
    });
    let mut prefs = load_prefs();
    let mut visible = false;
    emit(&sample(&prefs, Path::new("/sys/class/power_supply")));
    loop {
        let refresh = match rx.recv_timeout(Duration::from_secs(if visible { 5 } else { 30 })) {
            Ok(line) => {
                if let Ok(request) = serde_json::from_str::<Value>(&line) {
                    match request["op"].as_str() {
                        Some("visible") => {
                            visible = request["value"] == true;
                            visible
                        }
                        Some("refresh") => true,
                        Some("preferences") => {
                            let mut next = prefs.clone();
                            if let Some(changes) = request["changes"].as_object() {
                                for (k, v) in changes {
                                    if valid_preference(k, v) {
                                        next[k] = v.clone();
                                    }
                                }
                            }
                            match save_prefs(&next) {
                                Ok(()) => {
                                    prefs = next;
                                    emit(&json!({"type":"preferences","preferences":prefs}));
                                }
                                Err(e) => emit(&json!({"type":"error","message":e})),
                            };
                            false
                        }
                        _ => false,
                    }
                } else {
                    false
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => true,
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        };
        if refresh {
            emit(&sample(&prefs, Path::new("/sys/class/power_supply")));
        }
    }
}
fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("monitor") => monitor(),
        Some("sample") => emit(&sample(&load_prefs(), Path::new("/sys/class/power_supply"))),
        Some("action") => {
            let result = args
                .get(2)
                .ok_or("Missing request".to_owned())
                .and_then(|s| serde_json::from_str(s).map_err(|e| e.to_string()))
                .and_then(|r| action(&r));
            match result {
                Ok(message) => emit(&json!({"ok":true,"message":message})),
                Err(message) => {
                    emit(&json!({"ok":false,"message":message}));
                    std::process::exit(1);
                }
            }
        }
        _ => {
            eprintln!(
                "Usage: battery-studio monitor | sample | action '{{\"op\":...,\"args\":[...]}}'"
            );
            std::process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_capability_ranges_and_discrete_values() {
        assert_eq!(
            capability(
                "Stop threshold: true (values: [50 80 100])",
                "Stop threshold:"
            )["values"],
            json!([50, 80, 100])
        );
        assert_eq!(
            capability("Start threshold: true (range: 50..95)", "Start threshold:")["min"],
            50
        );
        assert_eq!(
            capability("Stop threshold: false", "Stop threshold:")["supported"],
            false
        );
        assert_eq!(capability("garbage", "Stop threshold:")["supported"], false);
    }
    #[test]
    fn rejects_bad_actions_without_spawning_processes() {
        for request in [
            json!([80, 20]),
            json!([-1, 80]),
            json!([0, 101]),
            json!([40, 40]),
            json!(["40", 80]),
        ] {
            assert!(action_args("threshold", request.as_array().unwrap()).is_err());
        }
        assert!(action_args("preset", &[json!("--help")]).is_err());
        assert!(action_args("persist", &[json!("enable")]).is_err());
        assert!(action_args("shell", &[]).is_err());
        assert!(action_args("threshold", &[json!(0), json!(100)]).is_ok());
    }
    #[test]
    fn parses_missing_and_valid_thresholds() {
        assert_eq!(
            thresholds("Thresholds: start=20% stop=80%"),
            json!({"start":20,"stop":80})
        );
        assert_eq!(
            thresholds("Thresholds: error reading"),
            json!({"start":null,"stop":null})
        );
    }
    #[test]
    fn aggregate_is_weighted_and_handles_opposing_flows() {
        let a = json!({"id":"BAT0","energy_wh":10,"full_wh":20,"power_w":10,"status":"Charging"});
        let b = json!({"id":"BAT1","energy_wh":30,"full_wh":60,"power_w":5,"status":"Discharging"});
        let both = aggregate(&[a.clone(), b]);
        assert_eq!(both["percent"], 50.0);
        assert_eq!(both["power_w"], 5.0);
        assert_eq!(both["hours"], 8.0);
        assert_eq!(aggregate(std::slice::from_ref(&a)), a);
        assert!(aggregate(&[]).is_null());
    }
    #[test]
    fn reads_sysfs_charge_units_and_missing_metrics() {
        let dir = env::temp_dir().join(format!("battery-studio-test-{}", std::process::id()));
        let battery_dir = dir.join("BAT0");
        fs::create_dir_all(&battery_dir).unwrap();
        for (name, value) in [
            ("voltage_now", "10000000"),
            ("charge_now", "2000000"),
            ("charge_full", "4000000"),
            ("charge_full_design", "5000000"),
            ("current_now", "-1000000"),
            ("capacity", "50"),
            ("status", "Discharging"),
        ] {
            fs::write(battery_dir.join(name), value).unwrap();
        }
        let bat = battery(&battery_dir, "Backend: ThinkPad\n\nBAT0 (Vendor Model)\n  Thresholds: start=20% stop=80%\n  Behaviour: auto\n\nPersistence: boot=false");
        assert_eq!(bat["energy_wh"], 20.0);
        assert_eq!(bat["power_w"], 10.0);
        assert_eq!(bat["health"], 80.0);
        assert_eq!(bat["hours"], 2.0);
        assert_eq!(bat["limits"]["stop"], 80);
        assert!(bat["cycles"].is_null());
        fs::write(battery_dir.join("status"), "Not charging").unwrap();
        assert!(battery(&battery_dir, "")["hours"].is_null());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn parses_only_kernel_advertised_charge_behaviours() {
        assert_eq!(
            behaviour_state("[auto] inhibit-charge force-discharge"),
            json!({"current":"auto","available":["auto","inhibit-charge","force-discharge"]})
        );
        assert_eq!(
            behaviour_state("auto [inhibit-charge]"),
            json!({"current":"inhibit-charge","available":["auto","inhibit-charge"]})
        );
        assert_eq!(
            behaviour_state("auto [force-discharge]")["current"],
            "force-discharge"
        );
        assert_eq!(
            behaviour_state("[unknown] arbitrary")["available"],
            json!([])
        );
        assert!(behaviour_state("")["current"].is_null());
    }
    #[test]
    fn validates_battery_and_mode_before_privileged_writes() {
        let dir = env::temp_dir().join(format!(
            "battery-studio-behaviour-test-{}",
            std::process::id()
        ));
        let battery_dir = dir.join("BAT0");
        fs::create_dir_all(&battery_dir).unwrap();
        fs::write(battery_dir.join("type"), "Battery").unwrap();
        fs::write(
            battery_dir.join("charge_behaviour"),
            "[auto] inhibit-charge force-discharge",
        )
        .unwrap();
        for mode in BEHAVIOURS {
            let (path, value) = behaviour_target(&dir, &[json!("BAT0"), json!(mode)]).unwrap();
            assert_eq!(path, battery_dir.join("charge_behaviour"));
            assert_eq!(&value, mode);
        }
        for args in [
            json!(["../BAT0", "auto"]),
            json!(["BAT0/../BAT0", "auto"]),
            json!(["BAT1", "auto"]),
            json!(["BAT0", "auto; reboot"]),
            json!(["BAT0", true]),
            json!(["BAT0"]),
        ] {
            assert!(behaviour_target(&dir, args.as_array().unwrap()).is_err());
        }
        fs::write(
            battery_dir.join("charge_behaviour"),
            "[auto] inhibit-charge",
        )
        .unwrap();
        assert!(behaviour_target(&dir, &[json!("BAT0"), json!("force-discharge")]).is_err());
        fs::write(battery_dir.join("type"), "Mains").unwrap();
        assert!(behaviour_target(&dir, &[json!("BAT0"), json!("auto")]).is_err());
        fs::write(battery_dir.join("type"), "Battery").unwrap();
        fs::write(battery_dir.join("present"), "0").unwrap();
        assert!(behaviour_target(&dir, &[json!("BAT0"), json!("auto")]).is_err());
        fs::remove_dir_all(dir).unwrap();
    }
    #[test]
    fn validates_preferences() {
        assert!(!valid_preference("display_mode", &json!("bad")));
        assert!(!valid_preference("retention_days", &json!(30)));
        assert!(!valid_preference("language", &json!("pt")));
        assert!(valid_preference("display_mode", &json!("icon")));
    }
}
