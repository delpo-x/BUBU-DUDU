extends Node
## Autoload "Sfx": placeholder audio synthesized at startup, no external assets.
##
## - play(name, pitch_jitter): one-shot effects from a small voice pool on the SFX bus.
## - play_music(theme): a soft generative loop (pad + pentatonic pluck) on the Music bus.
## Everything is generated in code so it can be swapped for real assets later by
## replacing _streams entries with loaded AudioStreams.

const MIX_RATE := 22050
const VOICES := 10

## theme name -> [root_hz, bpm, brightness 0..1]
const MUSIC_THEMES := {
	"menu": [220.0, 72.0, 0.5],
	"ch1": [261.63, 84.0, 0.7],
	"ch2": [233.08, 76.0, 0.55],
	"ch3": [293.66, 92.0, 0.8],
	"ch4": [196.0, 66.0, 0.45],
	"credits": [246.94, 70.0, 0.6],
}
const PENTATONIC := [0, 2, 4, 7, 9, 12, 14, 16]

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_played: Dictionary = {}

var _music_player: AudioStreamPlayer
var _music_playback: AudioStreamGeneratorPlayback
var _music_theme: String = ""
var _rng := RandomNumberGenerator.new()

# Generative music state.
var _t: float = 0.0
var _beat_time: float = 0.0
var _beat_len: float = 0.7
var _root: float = 220.0
var _bright: float = 0.5
var _chord: Array[float] = []
var _bar: int = 0
var _pluck_freq: float = 0.0
var _pluck_amp: float = 0.0
var _pluck_phase: float = 0.0
var _pad_phases: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _melody_degree: int = 2
var _music_gain: float = 0.0
var _music_target_gain: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_voices.append(p)
	_build_library()

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.4
	_music_player.stream = gen
	# Generated audio must be mixed by the engine (the web default "sample" mode can't).
	_music_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_music_player)


func _process(delta: float) -> void:
	_music_gain = move_toward(_music_gain, _music_target_gain, delta * 0.5)
	if _music_playback != null:
		_fill_music()
	if _music_gain <= 0.0 and _music_target_gain <= 0.0 and _music_player.playing:
		_music_player.stop()
		_music_playback = null


## Plays a one-shot effect. Unknown names are ignored (a warning in debug builds).
func play(sfx_name: String, pitch_jitter: float = 0.04, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sfx_name)
	if stream == null:
		push_warning("Sfx: unknown sound '%s'" % sfx_name)
		return
	# Throttle identical sounds fired in the same few milliseconds.
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(sfx_name, -1000)) < 30:
		return
	_last_played[sfx_name] = now
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func has_sound(sfx_name: String) -> bool:
	return _streams.has(sfx_name)


func play_music(theme: String) -> void:
	if not MUSIC_THEMES.has(theme):
		theme = "menu"
	if theme == _music_theme and _music_player.playing:
		_music_target_gain = 1.0
		return
	_music_theme = theme
	var cfg: Array = MUSIC_THEMES[theme]
	_root = cfg[0]
	_beat_len = 60.0 / float(cfg[1])
	_bright = cfg[2]
	_bar = 0
	_beat_time = 0.0
	_new_chord()
	_music_target_gain = 1.0
	if not _music_player.playing:
		_music_gain = 0.0
		_music_player.play()
		_music_playback = _music_player.get_stream_playback() as AudioStreamGeneratorPlayback


func stop_music() -> void:
	_music_target_gain = 0.0


## Stops every voice and the music right away (quitting): no playback outlives the tree.
func stop_all() -> void:
	for v in _voices:
		v.stop()
		v.stream = null
	_music_player.stop()
	_music_playback = null
	_music_theme = ""


func _exit_tree() -> void:
	stop_all()


# --- Music synthesis -----------------------------------------------------------

func _semitone(base: float, steps: int) -> float:
	return base * pow(2.0, steps / 12.0)


func _new_chord() -> void:
	# I - vi - IV - V style movement on the pentatonic root, gentle and warm.
	var progression := [0, 9, 5, 7]
	var root_step: int = progression[_bar % progression.size()]
	var base := _semitone(_root * 0.5, root_step)
	_chord = [base, _semitone(base, 7), _semitone(base, 12), _semitone(base, 16 if root_step != 9 else 15)]


func _fill_music() -> void:
	var frames := _music_playback.get_frames_available()
	if frames <= 0:
		return
	var dt := 1.0 / MIX_RATE
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in frames:
		_t += dt
		_beat_time += dt
		if _beat_time >= _beat_len:
			_beat_time -= _beat_len
			_on_beat()
		var s := 0.0
		# Soft pad: four triangle-ish voices.
		for v in 4:
			_pad_phases[v] = fmod(_pad_phases[v] + _chord[v] * dt, 1.0)
			var ph: float = _pad_phases[v]
			s += (absf(ph * 4.0 - 2.0) - 1.0) * 0.045
		# Pluck melody.
		if _pluck_amp > 0.0005:
			_pluck_phase = fmod(_pluck_phase + _pluck_freq * dt, 1.0)
			s += sin(_pluck_phase * TAU) * _pluck_amp * (0.6 + 0.4 * _bright)
			_pluck_amp *= 0.99975
		s *= _music_gain * 0.8
		buf[i] = Vector2(s, s)
	_music_playback.push_buffer(buf)


func _on_beat() -> void:
	var beats_in_bar := 4
	var beat_index := int(_t / _beat_len) % beats_in_bar
	if beat_index == 0:
		_bar += 1
		_new_chord()
	# Melody: random walk on the pentatonic scale, rests keep it calm.
	if _rng.randf() < 0.35 + _bright * 0.4:
		_melody_degree = clampi(_melody_degree + _rng.randi_range(-2, 2), 0, PENTATONIC.size() - 1)
		_pluck_freq = _semitone(_root, PENTATONIC[_melody_degree])
		_pluck_amp = 0.11
		_pluck_phase = 0.0


# --- Effect synthesis ----------------------------------------------------------

func _build_library() -> void:
	_streams["jump"] = _sweep(330.0, 620.0, 0.12, "square", 0.18)
	_streams["jump_heavy"] = _sweep(200.0, 380.0, 0.14, "square", 0.2)
	_streams["land"] = _noise(0.07, 0.35, 1800.0)
	_streams["land_heavy"] = _noise(0.12, 0.5, 900.0)
	_streams["plate_on"] = _tones([520.0, 780.0], 0.06, "sine", 0.3)
	_streams["plate_off"] = _tones([780.0, 520.0], 0.06, "sine", 0.25)
	_streams["gate_open"] = _sweep(140.0, 300.0, 0.4, "triangle", 0.35)
	_streams["gate_close"] = _sweep(300.0, 140.0, 0.35, "triangle", 0.3)
	_streams["pickup"] = _sweep(660.0, 990.0, 0.08, "sine", 0.3)
	_streams["drop"] = _sweep(380.0, 220.0, 0.09, "sine", 0.3)
	_streams["throw"] = _noise(0.15, 0.25, 4000.0)
	_streams["balloon"] = _sweep(600.0, 950.0, 0.45, "sine", 0.25, 9.0)
	_streams["pop"] = _tones([1200.0, 900.0], 0.04, "sine", 0.35)
	_streams["respawn"] = _tones([523.25, 659.25, 783.99], 0.07, "triangle", 0.3)
	_streams["collect"] = _tones([659.25, 783.99, 987.77, 1318.5], 0.09, "sine", 0.3)
	_streams["hug"] = _chord_tone([392.0, 493.88, 587.33], 0.9, 0.22)
	_streams["bounce"] = _sweep(220.0, 760.0, 0.2, "sine", 0.35)
	_streams["break"] = _noise(0.35, 0.5, 1200.0)
	_streams["call"] = _sweep(420.0, 1250.0, 0.35, "triangle", 0.3, 14.0)
	_streams["nope"] = _tones([170.0, 150.0], 0.08, "square", 0.18)
	_streams["ui_move"] = _tones([880.0], 0.03, "sine", 0.2)
	_streams["ui_accept"] = _sweep(660.0, 990.0, 0.07, "sine", 0.28)
	_streams["ui_back"] = _sweep(660.0, 440.0, 0.07, "sine", 0.25)
	_streams["text"] = _tones([1150.0], 0.018, "sine", 0.08)
	_streams["exit_ready"] = _tones([783.99, 987.77], 0.1, "sine", 0.25)
	_streams["lever"] = _tones([300.0, 450.0], 0.04, "square", 0.18)
	_streams["piggy_on"] = _sweep(440.0, 700.0, 0.12, "sine", 0.3)
	_streams["piggy_off"] = _sweep(700.0, 440.0, 0.12, "sine", 0.25)
	_streams["launch"] = _sweep(180.0, 900.0, 0.3, "triangle", 0.35)
	_streams["wind"] = _noise(0.6, 0.12, 2500.0)
	_streams["chapter"] = _chord_tone([261.63, 329.63, 392.0, 523.25], 1.6, 0.2)
	_streams["timer_tick"] = _tones([1400.0], 0.02, "sine", 0.12)


func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"triangle":
			return absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0
		_:
			return sin(phase * TAU)


func _env(t: float, length: float) -> float:
	var attack := minf(0.008, length * 0.2)
	if t < attack:
		return t / attack
	return pow(1.0 - (t - attack) / maxf(length - attack, 0.0001), 2.0)


func _sweep(f0: float, f1: float, length: float, kind: String, vol: float, vibrato: float = 0.0) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := lerpf(f0, f1, t / length)
		if vibrato > 0.0:
			f *= 1.0 + 0.03 * sin(t * vibrato * TAU)
		phase += f / MIX_RATE
		out[i] = _osc(kind, phase) * _env(t, length) * vol
	return _make_wav(out)


func _tones(freqs: Array, each: float, kind: String, vol: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	for f: float in freqs:
		var n := int(each * MIX_RATE)
		var phase := 0.0
		for i in n:
			var t := float(i) / MIX_RATE
			phase += f / MIX_RATE
			out.append(_osc(kind, phase) * _env(t, each) * vol)
	return _make_wav(out)


func _chord_tone(freqs: Array, length: float, vol: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var s := 0.0
		for f: float in freqs:
			s += sin(t * f * TAU)
		var attack := minf(t / 0.05, 1.0)
		out[i] = s / freqs.size() * attack * pow(1.0 - t / length, 1.5) * vol * 1.6
	return _make_wav(out)


func _noise(length: float, vol: float, cutoff: float) -> AudioStreamWAV:
	var n := int(length * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff)
	var y := 0.0
	var a := clampf(cutoff / MIX_RATE * TAU, 0.0, 1.0)
	for i in n:
		var t := float(i) / MIX_RATE
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * _env(t, length) * vol * 2.0
	return _make_wav(out)
