extends Node
## Autoload "Voices": synthesized babble for Bubu and Dudu (Animal Crossing style), no assets.
##
## - speak(who, shown, full, mood): one syllable for the letter just revealed in a dialogue.
## - emote(who, mood): a short vocal reaction when a line with that mood starts (laugh, sob...).
## - action(who, kind): a little grunt for jump, fall, call, piggyback, hug.
##
## Each voice is a bank of vowel syllables (a e i o u) built from harmonics shaped by rough
## vowel formants, plus a trembling "sad" copy. Pitch follows the character, the mood and a
## question mark. A real recording can replace any of it: put art/voices/<who>_<name>.wav
## (or .ogg) where <name> is a vowel ("a"), an emote mood ("laugh") or an action ("jump").

const MIX_RATE := 22050
const VOICES := 4
const VOWELS := ["a", "e", "i", "o", "u"]
## Vowel -> [F1, F2] in Hz (rough, for a cartoon voice).
const FORMANTS := {
	"a": [800.0, 1250.0], "e": [500.0, 1800.0], "i": [320.0, 2300.0],
	"o": [500.0, 900.0], "u": [350.0, 700.0],
}
## Character -> [base pitch Hz, syllable seconds, brightness 0..1, volume dB].
const CHARACTERS := {
	"bubu": [330.0, 0.07, 0.8, -9.0],
	"dudu": [185.0, 0.085, 0.45, -7.0],
}
## Mood -> [semitones, sad tremble]. Moods not listed speak normally.
const MOODS := {
	"laugh": [3.0, false], "happy": [3.0, false], "cheers": [3.0, false], "hey": [2.0, false],
	"cute": [2.0, false], "smug": [1.0, false], "handsome": [1.0, false], "pig": [2.0, false],
	"snack": [1.0, false], "dizzy": [-1.0, true],
	"cry": [-2.0, true], "teary": [-1.0, true], "worried": [-1.0, true], "sulk": [-3.0, false],
	"grudge": [-2.0, false], "mad": [-2.0, false], "wave": [2.0, false], "piggy": [2.0, false], "sus": [-1.0, false], "think": [-1.0, false], "bed": [-2.0, false],
}
## Mood -> syllables of its reaction: [vowel, semitones, seconds].
const EMOTES := {
	"laugh": [["a", 4.0, 0.06], ["a", 6.0, 0.06], ["a", 8.0, 0.09]],
	"cheers": [["e", 2.0, 0.07], ["i", 7.0, 0.12]],
	"cry": [["u", 0.0, 0.16], ["u", -2.0, 0.22]],
	"teary": [["u", 1.0, 0.18]],
	"sulk": [["u", -4.0, 0.1], ["u", -6.0, 0.07]],
	"sus": [["e", -2.0, 0.08], ["e", 3.0, 0.11]],
	"nope": [["o", 0.0, 0.07], ["o", -2.0, 0.07], ["o", -4.0, 0.09]],
	"worried": [["o", 2.0, 0.09], ["o", 0.0, 0.12]],
	"hey": [["e", 4.0, 0.06], ["i", 7.0, 0.1]],
	"dizzy": [["u", 3.0, 0.08], ["a", -1.0, 0.08], ["u", -5.0, 0.12]],
	"think": [["u", 0.0, 0.18]],
	"mad": [["a", -3.0, 0.05], ["a", -3.0, 0.05], ["a", -1.0, 0.1]],
	"wave": [["e", 4.0, 0.06], ["i", 7.0, 0.1]],
	"smug": [["e", 0.0, 0.06], ["e", 5.0, 0.08]],
}
## Action -> syllables, like EMOTES.
const ACTIONS := {
	"jump": [["u", 5.0, 0.06]],
	"fall": [["a", 7.0, 0.1], ["a", 2.0, 0.12], ["a", -3.0, 0.14]],
	"call": [["e", 5.0, 0.08], ["i", 9.0, 0.14]],
	"piggy": [["o", 3.0, 0.06], ["o", 7.0, 0.08]],
	"hug": [["u", 0.0, 0.1], ["u", 4.0, 0.16]],
	"nope": [["o", 0.0, 0.06], ["o", -3.0, 0.08]],
}
## Characters between two syllables while text types.
const EVERY := 2

var _banks: Dictionary = {}       # "who:vowel" / "who:vowel:sad" -> AudioStreamWAV
var _recorded: Dictionary = {}    # "who_name" -> AudioStream (art/voices)
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	for who: String in CHARACTERS.keys():
		for v: String in VOWELS:
			_banks["%s:%s" % [who, v]] = _syllable(who, v, false)
			_banks["%s:%s:sad" % [who, v]] = _syllable(who, v, true)


func enabled() -> bool:
	return GameState.voices_enabled


## Call each time a dialogue reveals more text; plays a syllable every few letters.
func speak(who: String, shown: String, full: String, mood: String = "") -> void:
	if not enabled() or not CHARACTERS.has(who) or shown.is_empty():
		return
	if shown.length() % EVERY != 0:
		return
	var c := shown.substr(shown.length() - 1, 1).to_lower()
	if c == " " or ".,;:!?…«»-".contains(c):
		return
	var vowel := _vowel_for(shown)
	var m: Array = MOODS.get(mood, [0.0, false])
	var semi := float(m[0]) + _rng.randf_range(-1.5, 1.5)
	# A question rises over its last stretch.
	if full.strip_edges().ends_with("?") and shown.length() > full.length() * 0.7:
		semi += 3.0
	var rec := _recorded_stream(who, vowel)
	_play(rec if rec != null else _banks["%s:%s%s" % [who, vowel, ":sad" if bool(m[1]) else ""]], semi, float(CHARACTERS[who][3]))


## A short vocal reaction for a mood (laugh, sob, "eh?").
func emote(who: String, mood: String) -> void:
	if not enabled() or not CHARACTERS.has(who):
		return
	var rec := _recorded_stream(who, mood)
	if rec != null:
		_play(rec, 0.0, float(CHARACTERS[who][3]) + 2.0)
		return
	if EMOTES.has(mood):
		_sequence(who, EMOTES[mood], bool((MOODS.get(mood, [0.0, false]) as Array)[1]))


## A grunt for something a character does in play.
func action(who: String, kind: String) -> void:
	if not enabled() or not CHARACTERS.has(who):
		return
	var rec := _recorded_stream(who, kind)
	if rec != null:
		_play(rec, _rng.randf_range(-0.5, 0.5), float(CHARACTERS[who][3]) + 1.0)
		return
	if ACTIONS.has(kind):
		_sequence(who, ACTIONS[kind], false)


# --- Internals -------------------------------------------------------------------------

func _sequence(who: String, sylls: Array, sad: bool) -> void:
	for s: Array in sylls:
		_play(_banks["%s:%s%s" % [who, s[0], ":sad" if sad else ""]], float(s[1]), float(CHARACTERS[who][3]) + 2.0)
		await get_tree().create_timer(float(s[2]), true, false, true).timeout


func _play(stream: AudioStream, semitones: float, volume_db: float) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pow(2.0, semitones / 12.0)
	p.play()


## Vowel of the syllable the last letter belongs to (the nearest vowel back in the text).
func _vowel_for(shown: String) -> String:
	var map := {"à": "a", "è": "e", "é": "e", "ì": "i", "ò": "o", "ù": "u", "y": "i"}
	for i in range(shown.length() - 1, maxi(shown.length() - 5, -1), -1):
		var c := shown.substr(i, 1).to_lower()
		c = map.get(c, c)
		if VOWELS.has(c):
			return c
	return VOWELS[shown.length() % VOWELS.size()]


func _recorded_stream(who: String, name_: String) -> AudioStream:
	var key := "%s_%s" % [who, name_]
	if not _recorded.has(key):
		var found: AudioStream = null
		for ext in ["wav", "ogg"]:
			var path := "res://art/voices/%s.%s" % [key, ext]
			if ResourceLoader.exists(path):
				found = load(path) as AudioStream
				break
		_recorded[key] = found
	return _recorded[key]


## One vowel syllable: harmonics of the pitch weighted by two formant bumps, a quick
## attack, a soft tail and a little pitch drop (sounds like a tiny spoken "ba").
func _syllable(who: String, vowel: String, sad: bool) -> AudioStreamWAV:
	var cfg: Array = CHARACTERS[who]
	var f0 := float(cfg[0])
	var length := float(cfg[1]) * (1.6 if sad else 1.0)
	var bright := float(cfg[2])
	var fm: Array = FORMANTS[vowel]
	var n := int(length * MIX_RATE)
	var weights: Array[float] = []
	for h in range(1, 13):
		var f := f0 * h
		var w := 0.0
		for k in 2:
			var d := (f - float(fm[k])) / (160.0 + 90.0 * k)
			w += exp(-d * d) * (1.0 if k == 0 else 0.6 * bright)
		weights.append(w / h + (0.5 if h == 1 else 0.0))
	var out := PackedByteArray()
	out.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var f := f0 * (1.0 - 0.06 * t / length)
		if sad:
			f *= 1.0 + 0.035 * sin(t * 11.0 * TAU)
		phase += f / MIX_RATE
		var s := 0.0
		for h in weights.size():
			s += sin(phase * TAU * (h + 1)) * weights[h]
		var env := minf(t / 0.006, 1.0) * pow(1.0 - t / length, 1.6)
		out.encode_s16(i * 2, int(clampf(s * env * 0.32, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = out
	return wav
