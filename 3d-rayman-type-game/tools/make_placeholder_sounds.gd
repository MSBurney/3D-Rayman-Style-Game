extends SceneTree

## Generates the placeholder sound effects in assets/audio/ as .wav files.
##
## The project ships with no recorded audio, so these are synthesised from simple
## waveforms — enough to make actions feel responsive and to prove the wiring
## works. They are meant to be REPLACED with real sounds; nothing depends on
## these exact files beyond their paths.
##
## Run it from the project root:
##   <godot> --headless --path . --script res://tools/make_placeholder_sounds.gd
##
## Tweak the recipes in _init() and re-run to hear something different. Each
## sound is described by a starting pitch, an ending pitch, a length, and a
## waveform — that is genuinely all a retro blip is.

const RATE := 22050
const OUT_DIR := "res://assets/audio"

enum Wave { SINE, SQUARE, NOISE }


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# name,          from Hz, to Hz, seconds, wave,        volume
	_write("lum",        880.0, 1760.0, 0.14, Wave.SINE,   0.35)
	_write("lum_red",    520.0, 1040.0, 0.30, Wave.SINE,   0.35)
	_write("jump",       320.0,  640.0, 0.13, Wave.SQUARE, 0.22)
	_write("land",       220.0,   90.0, 0.10, Wave.SQUARE, 0.20)
	_write("punch",      600.0,  180.0, 0.12, Wave.NOISE,  0.25)
	_write("hurt",       400.0,  140.0, 0.26, Wave.SQUARE, 0.28)
	_write("enemy_hit",  300.0,  520.0, 0.10, Wave.SQUARE, 0.25)
	_write("enemy_die",  520.0,   80.0, 0.34, Wave.NOISE,  0.28)
	_write("grapple",    240.0,  900.0, 0.18, Wave.SINE,   0.25)
	_write("checkpoint", 660.0, 1320.0, 0.36, Wave.SINE,   0.30)

	print("Wrote placeholder sounds to ", OUT_DIR)
	quit()


func _write(name: String, from_hz: float, to_hz: float, seconds: float,
		wave: Wave, volume: float) -> void:
	var frames := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(frames)

	var phase := 0.0
	for i in frames:
		var t := float(i) / float(frames)          # 0 -> 1 across the sound
		var hz: float = lerpf(from_hz, to_hz, t)

		# Advance the phase by one sample's worth of this frequency. Doing it
		# incrementally (rather than sin(hz * time)) keeps the wave continuous
		# while the pitch slides.
		phase += TAU * hz / float(RATE)

		var value := 0.0
		match wave:
			Wave.SINE:
				value = sin(phase)
			Wave.SQUARE:
				value = 1.0 if sin(phase) >= 0.0 else -1.0
			Wave.NOISE:
				value = randf_range(-1.0, 1.0)

		# Fade in fast, out slowly. Without the fade-in you get an audible click
		# at the start; without the fade-out the sound ends abruptly.
		var envelope: float = minf(t / 0.02, 1.0) * pow(1.0 - t, 1.6)
		samples[i] = value * envelope * volume

	_save_wav(name, samples)


## Writes 16-bit mono PCM. The 44-byte header is fixed boilerplate — the only
## parts that vary are the two sizes and the sample rate.
func _save_wav(name: String, samples: PackedFloat32Array) -> void:
	var pcm := PackedByteArray()
	for s in samples:
		var clamped: int = int(clampf(s, -1.0, 1.0) * 32767.0)
		pcm.append(clamped & 0xFF)
		pcm.append((clamped >> 8) & 0xFF)

	var data := PackedByteArray()
	data.append_array("RIFF".to_ascii_buffer())
	_put_u32(data, 36 + pcm.size())
	data.append_array("WAVEfmt ".to_ascii_buffer())
	_put_u32(data, 16)          # fmt chunk size
	_put_u16(data, 1)           # 1 = uncompressed PCM
	_put_u16(data, 1)           # mono
	_put_u32(data, RATE)
	_put_u32(data, RATE * 2)    # bytes per second
	_put_u16(data, 2)           # bytes per sample frame
	_put_u16(data, 16)          # bits per sample
	data.append_array("data".to_ascii_buffer())
	_put_u32(data, pcm.size())
	data.append_array(pcm)

	var path := "%s/%s.wav" % [OUT_DIR, name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("could not write " + path)
		return
	file.store_buffer(data)
	file.close()


func _put_u16(buffer: PackedByteArray, value: int) -> void:
	buffer.append(value & 0xFF)
	buffer.append((value >> 8) & 0xFF)


func _put_u32(buffer: PackedByteArray, value: int) -> void:
	for shift in [0, 8, 16, 24]:
		buffer.append((value >> shift) & 0xFF)
