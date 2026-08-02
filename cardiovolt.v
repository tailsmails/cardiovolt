import os
import json
import flag
import time

struct SensorRange {
mut:
	min i64
	max i64
}

fn main() {
	mut fp := flag.new_flag_parser(os.args)
	fp.application('CardioVolt')
	fp.version('2.0.2')
	fp.description('Hardware voltage anomaly detector with state-clustering')
	fp.skip_executable()

	duration := fp.int('duration', `d`, 10, 'Sampling duration in seconds')
	interval := fp.int('interval', `i`, 500, 'Sampling interval in milliseconds')
	margin := fp.float('margin', `m`, 5.0, 'Tolerance margin percentage')
	baseline_path := fp.string('file', `f`, 'voltage_baseline.json', 'Path to the baseline JSON file')
	verbose := fp.bool('verbose', `v`, false, 'Print all checked sensor values, not just anomalies')
	regulator_pattern := fp.string('regulator', `r`, '/sys/class/regulator/regulator.*/microvolts', 'Glob pattern for regulators')
	ps_pattern := fp.string('power', `p`, '/sys/class/power_supply/*/voltage_now', 'Glob pattern for power supplies')

	additional_args := fp.finalize() or {
		println(err)
		println(fp.usage())
		return
	}

	if additional_args.len < 1 {
		println('Error: Mode must be specified ("save" or "check").')
		println(fp.usage())
		return
	}

	mode := additional_args[0]

	if mode == 'save' {
		save_baseline(baseline_path, regulator_pattern, ps_pattern, duration, interval, margin)
	} else if mode == 'check' {
		check_anomaly(baseline_path, regulator_pattern, ps_pattern, margin, verbose)
	} else {
		println('Invalid mode! Use "save" or "check".')
	}
}

fn scan_voltages(regulator_pattern string, ps_pattern string) map[string]i64 {
	mut results := map[string]i64{}

	regulator_paths := os.glob(regulator_pattern) or { []string{} }
	for path in regulator_paths {
		val_str := os.read_file(path) or { continue }
		val := val_str.trim_space().i64()
		results[path] = val
	}

	ps_paths := os.glob(ps_pattern) or { []string{} }
	for path in ps_paths {
		val_str := os.read_file(path) or { continue }
		val := val_str.trim_space().i64()
		results[path] = val
	}

	return results
}

fn save_baseline(baseline_path string, regulator_pattern string, ps_pattern string, duration_sec int, interval_ms int, margin_percent f64) {
	println('Sampling voltages for ${duration_sec} seconds (interval: ${interval_ms}ms)...')
	mut baseline := map[string][]SensorRange{}

	total_samples := (duration_sec * 1000) / interval_ms
	step := if total_samples >= 10 { total_samples / 10 } else { 1 }

	for sample_idx in 0 .. total_samples {
		current := scan_voltages(regulator_pattern, ps_pattern)
		for path, val in current {
			mut ranges := baseline[path] or { []SensorRange{} }
			mut merged := false
			for i in 0 .. ranges.len {
				mut limit_min := f64(ranges[i].min) * (1.0 - margin_percent / 100.0)
				mut limit_max := f64(ranges[i].max) * (1.0 + margin_percent / 100.0)
				
				if limit_min > limit_max {
					temp := limit_min
					limit_min = limit_max
					limit_max = temp
				}

				if f64(val) >= limit_min && f64(val) <= limit_max {
					if val < ranges[i].min { ranges[i].min = val }
					if val > ranges[i].max { ranges[i].max = val }
					merged = true
					break
				}
			}
			if !merged {
				ranges << SensorRange{min: val, max: val}
			}
			baseline[path] = ranges
		}
		
		if (sample_idx + 1) % step == 0 {
			println('Progress: ${((sample_idx + 1) * 100) / total_samples}%...')
		}
		
		time.sleep(interval_ms * time.millisecond)
	}
	println('Sampling complete.')

	if baseline.len == 0 {
		println('Error: No voltage sensors found!')
		return
	}

	data := json.encode(baseline)
	os.write_file(baseline_path, data) or {
		println('Error saving baseline file: ${err}')
		return
	}
	println('Baseline successfully saved to "${baseline_path}".')
	println('Saved sensors: ${baseline.len}')
}

fn check_anomaly(baseline_path string, regulator_pattern string, ps_pattern string, margin_percent f64, verbose bool) {
	if !os.exists(baseline_path) {
		println('Error: Baseline file not found: ${baseline_path}. Run "save" first.')
		return
	}

	baseline_data := os.read_file(baseline_path) or {
		println('Error reading baseline file: ${err}')
		return
	}

	baseline := json.decode(map[string][]SensorRange, baseline_data) or {
		println('Error decoding baseline JSON: ${err}')
		return
	}

	println('Scanning and comparing current voltages...')
	current := scan_voltages(regulator_pattern, ps_pattern)

	mut anomalies_found := 0

	for path, ranges in baseline {
		curr_val := current[path] or {
			println('[!] Warning: Sensor is missing or unavailable: ${path}')
			anomalies_found++
			continue
		}

		mut in_range := false
		for r in ranges {
			mut limit_min := if r.min == 0 { f64(0) } else { f64(r.min) * (1.0 - margin_percent / 100.0) }
			mut limit_max := if r.max == 0 { f64(0) } else { f64(r.max) * (1.0 + margin_percent / 100.0) }
			
			if limit_min > limit_max {
				temp := limit_min
				limit_min = limit_max
				limit_max = temp
			}

			if f64(curr_val) >= limit_min && f64(curr_val) <= limit_max {
				in_range = true
				if verbose {
					println('[OK] ${path}: ${curr_val} uV is within range [${r.min}, ${r.max}]')
				}
				break
			}
		}

		if !in_range {
			println('[!] Anomaly detected in ${path}:')
			println('    Current:  ${curr_val} uV')
			println('    Allowed ranges (with ${margin_percent}% margin):')
			for r in ranges {
				mut limit_min := f64(r.min) * (1.0 - margin_percent / 100.0)
				mut limit_max := f64(r.max) * (1.0 + margin_percent / 100.0)
				
				if limit_min > limit_max {
					temp := limit_min
					limit_min = limit_max
					limit_max = temp
				}
				println('      [${limit_min:.1f}, ${limit_max:.1f}] uV')
			}
			anomalies_found++
		}
	}

	for path, curr_val in current {
		if path !in baseline {
			println('[!] New sensor detected: ${path} with voltage ${curr_val} uV')
			anomalies_found++
		}
	}

	if anomalies_found > 0 {
		println('\n[WARNING] Detected ${anomalies_found} suspect cases or state changes.')
	} else {
		println('\n[OK] All checked voltages are within normal limits.')
	}
}
