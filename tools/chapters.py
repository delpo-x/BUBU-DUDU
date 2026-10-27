"""The four chapters: each room is a list of beats composed left to right.

A room spec is a dict:
    beats   list of (beat_name, {kwargs}) or ("sign", id) / ("talk", id)
    hint    pause-menu hint (Italian)
    intro   optional dialogue id played on first entry
    call    True only where calling the partner is the lesson / harmless
Room height and the starting floor are computed from a dry run so every beat fits.
est_minutes comes from EFFORT (first-time co-op pair, one novice player).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beats as B  # noqa: E402
from roomkit import Builder  # noqa: E402

# Minutes a first-time pair spends on each beat (reading the room, failing, retrying).
EFFORT = {
    "flat": 0.25, "steps_up": 0.6, "steps_down": 0.3, "gap": 0.6,
    "boost_gate": 3.5, "two_plates": 3.0, "heavy_plate": 2.0, "cozy": 1.5, "call_lesson": 3.0,
    "crate_ledge": 3.5, "heavy_crate_plate": 3.5, "crate_plate_door": 3.5, "pulley": 5.0,
    "moving_cross": 1.5, "elevator": 4.5, "fragile_drop": 2.5, "walljump_shaft": 4.0,
    "seesaw": 5.0, "bounce_up": 1.5, "timed_pair": 3.0, "vine_climb": 1.5, "wind_lift": 4.5,
    "boost_memory": 2.0, "mystery_box": 0.4,
}
FAMILIARITY = [1.0, 0.65, 0.5, 0.42]
SEEN = {}
FRAME = 0.6          # entering, walking to the exit, looking around
CHAPTER_DIFFICULTY = {1: 1.0, 2: 1.1, 3: 1.15, 4: 1.25}

# Tiles of headroom a beat needs above its entry floor.
HEAD = {"seesaw": 8.5, "boost_gate": 4.5, "call_lesson": 4.5, "boost_memory": 4.5, "pulley": 5.5, "mystery_box": 5.0}


# Rooms estimated this long (minutes) or more get a lantern-checkpoint halfway.
LANTERN_MIN_EST = 7.0


def _head(name, kw, g_in, g_out):
    if name == "walljump_shaft":
        return kw.get("height", 6) + 3.5
    if name in HEAD:
        return HEAD[name]
    return 3.5 + max(0.0, g_in - g_out)


def _run_beats(b, beats, x, g, trace=None, lantern_after=-1):
    for i, item in enumerate(beats):
        name = item[0]
        if name == "sign":
            B.sign(b, x - 1.15, g, item[1])
            continue
        if name == "talk":
            B.talk(b, x - 1.0, g, item[1])
            continue
        kw = dict(item[1]) if len(item) > 1 else {}
        g_in = g
        x, g = getattr(B, name)(b, x, g, **kw)
        if trace is not None:
            trace.append((name, kw, g_in, g))
        if i == lantern_after:
            # A lantern-checkpoint on the ground just past the puzzle (mid-room save).
            B.checkpoint(b, x - 1.0, g)
    return x, g


def build_room(root, chapter, index, spec):
    rid = "c%d_r%02d" % (chapter, index + 1)
    beats = spec["beats"]
    # Dry run: find how far up and down the room goes.
    dry = Builder(rid, chapter, 400, 400, est=1, hint="-")
    trace = []
    x, g = B.start(dry, 200.0)
    _run_beats(dry, beats, x, g, trace)
    top = min([200.0 - 3.5] + [g_in - _head(n, kw, g_in, g_out) for n, kw, g_in, g_out in trace])
    bottom = max([200.0] + [max(g_in, g_out) for _, _, g_in, g_out in trace]) + 3.0
    h = max(12, int(math.ceil(bottom - top)))
    assert h <= 20, "%s: room too tall (%d)" % (rid, h)
    g0 = 200.0 - (bottom - h)  # keep the bottom margin; extra height goes on top

    est = FRAME
    efforts = []
    for n, kw, _, _ in trace:
        # A puzzle seen before goes faster: full effort the first time, then less.
        seen = SEEN.get(n, 0)
        SEEN[n] = seen + 1
        efforts.append(EFFORT[n] * FAMILIARITY[min(seen, len(FAMILIARITY) - 1)])
        est += efforts[-1]
    est = round(est * CHAPTER_DIFFICULTY[chapter], 1)
    # Long rooms get a lantern once about half of the puzzle effort is behind the players.
    lantern_after = -1
    if est >= LANTERN_MIN_EST and len(efforts) >= 2:
        done, half = 0.0, sum(efforts) / 2.0
        steps = [i for i, item in enumerate(beats) if item[0] not in ("sign", "talk")]
        for k, e in enumerate(efforts[:-1]):
            done += e
            if done >= half:
                lantern_after = steps[k]
                break
    b = Builder(rid, chapter, 400, h, est=est, hint=spec["hint"], intro=spec.get("intro", ""),
                call=spec.get("call", False), seed=chapter * 100 + index)
    if spec.get("intro"):
        b.dialogues.append(spec["intro"])
    x, g = B.start(b, g0)
    x, g = _run_beats(b, beats, x, g, lantern_after=lantern_after)
    x, g = B.exit_door(b, x, g)
    b.w = int(math.ceil(x + 1))
    return b.write(root), b


def _r(*beats, hint, intro="", call=False):
    out = []
    for item in beats:
        if isinstance(item, str):
            out.append((item, {}))
        else:
            out.append(item)
    return dict(beats=out, hint=hint, intro=intro, call=call)


def S(dialogue):
    return ("sign", dialogue)


def TALK(dialogue):
    return ("talk", dialogue)


def P(name, **kw):
    return (name, kw)


# --- Chapter 1: Il prato --------------------------------------------------------------------
CH1 = [
    _r(S("c1_sign_move"), P("flat", n=3), P("steps_up", k=2), P("steps_down", k=2), P("gap", w=1.5),
       P("flat", n=3), hint="Stick sinistro per camminare, A per saltare. Tieni premuto A per saltare più in alto.",
       intro="c1_r01_in"),
    _r(P("gap", w=2.0), P("steps_up", k=3), P("gap", w=2.0), P("steps_down", k=3), TALK("c1_r02_talk"),
       P("flat", n=3), P("mystery_box", mem="m1_f"),
       hint="Prendete la rincorsa e saltate all'ultimo momento: il gioco perdona i salti tardivi."),
    _r(S("c1_sign_piggy"), P("boost_gate"), P("flat", n=3),
       hint="Bubu salta in groppa a Dudu con Y vicino a lui; poi A per un salto spinto, più alto del normale.",
       intro="c1_r03_in"),
    _r(S("c1_sign_plate"), P("two_plates"), P("gap", w=1.5), P("steps_up", k=2), P("two_plates"), P("steps_down", k=2),
       hint="Una piastra tiene aperta la porta solo finché qualcuno ci sta sopra. Ce n'è una per lato."),
    _r(P("steps_up", k=1), P("heavy_plate"), P("steps_down", k=1), P("boost_memory", mem="m1_a"),
       hint="Alcune piastre sono pesanti: servono tutti e due insieme. Il ricordo è in alto: in groppa!"),
    _r(S("c1_sign_hug"), P("cozy", dialogue="c1_cozy_a", mem="m1_b"), P("flat", n=3),
       hint="Nei posti accoglienti premete Y insieme, entrambi dentro il cerchio di luce.",
       intro="c1_r06_in"),
    _r(S("c1_sign_call"), P("call_lesson"), P("flat", n=3), P("gap", w=2.0), P("call_lesson"),
       hint="Se uno dei due resta indietro, chi è avanti tiene premuto Y per chiamarlo.", call=True),
    _r(P("boost_gate"), P("two_plates"), TALK("c1_r08_talk"), P("heavy_plate"),
       hint="Prima la leva in alto (salto spinto), poi una piastra per lato."),
    _r(P("two_plates", bridge=True), P("gap", w=2.0), P("boost_memory", mem="m1_c"), P("boost_gate"),
       hint="Il ponte appare solo mentre qualcuno è su una piastra. Chi resta indietro poi raggiunge l'altro."),
    _r(P("heavy_plate"), P("steps_up", k=2), P("boost_gate", mem="m1_d"), P("steps_down", k=2),
       hint="Pesate insieme sulla piastra grande; la leva alta si raggiunge solo con un salto spinto.",
       intro="c1_r10_in"),
    _r(P("steps_up", k=3), P("two_plates"), P("gap", w=2.0), P("heavy_plate"), P("steps_down", k=2),
       P("two_plates", bridge=True), P("boost_gate"),
       hint="Una piastra per lato per la prima porta, tutti e due insieme per la seconda."),
    _r(P("two_plates", bridge=True), P("boost_gate"), P("heavy_plate"), P("cozy", required=False, dialogue="c1_cozy_b"),
       P("two_plates"),
       hint="Ponte: uno tiene la piastra, l'altro attraversa e preme quella dall'altra parte."),
    _r(P("gap", w=2.0), P("call_lesson"), P("steps_up", k=2), P("gap", w=2.0), P("steps_down", k=2),
       TALK("c1_r13_talk"), hint="Salto spinto oltre lo steccato, poi chiamata con Y tenuto premuto.", call=True),
    _r(P("boost_gate"), P("heavy_plate"), P("two_plates", bridge=True), P("gap", w=2.0), P("two_plates"),
       P("boost_gate"), P("cozy", dialogue="c1_cozy_c", mem="m1_e"),
       hint="Leva in alto, piastra pesante, ponte. Alla fine, un abbraccio.", intro="c1_r14_in"),
]

# --- Chapter 2: Il borgo ---------------------------------------------------------------------
CH2 = [
    _r(S("c2_sign_crate"), P("flat", n=2), P("crate_ledge"), P("flat", n=3),
       hint="B per raccogliere una cassa, di nuovo B per posarla. Usatela come gradino.", intro="c2_r01_in"),
    _r(S("c2_sign_heavy"), P("heavy_crate_plate"), P("gap", w=1.5), P("boost_gate"),
       hint="Solo Dudu solleva la cassa pesante. Una cassa sulla piastra fa da peso al posto vostro."),
    _r(P("crate_plate_door"), P("steps_up", k=2), P("moving_cross", span=6), P("steps_down", k=2),
       hint="La piastra vuole un peso fisso: la cassa piccola basta. La piattaforma aspetta voi due."),
    _r(S("c2_sign_pulley"), P("pulley", mem="m2_a"),
       hint="La carrucola: il più pesante scende, l'altro sale. Dudu pesa più di Bubu.", intro="c2_r04_in"),
    _r(P("elevator", height=4), P("steps_down", k=2), P("gap", w=2.0), TALK("c2_r05_talk"), P("crate_ledge"),
       P("steps_down", k=2),
       hint="L'ascensore sale finché una delle due piastre è premuta. Fate a turno."),
    _r(P("crate_ledge"), P("fragile_drop", depth=3), P("two_plates"), P("boost_memory", mem="m2_b"),
       hint="Le assi crepate reggono Bubu ma non Dudu. A volte la strada è giù."),
    _r(S("c2_sign_wall"), P("walljump_shaft", height=6, mem="m2_c"), P("flat", n=3),
       P("mystery_box", mem="m2_f"), hint="Bubu salta tra le pareti scanalate: spingi verso la parete e premi A quando la tocchi.",
       intro="c2_r07_in"),
    _r(P("heavy_crate_plate"), P("moving_cross", span=6), P("cozy", dialogue="c2_cozy_a", mem="m2_d"),
       hint="Dudu porta la cassa pesante sulla piastra; poi un momento per voi."),
    _r(P("pulley"), P("moving_cross", span=7), P("crate_plate_door"),
       hint="Carrucola, traghetto, poi la cassa piccola fa da peso sulla piastra."),
    _r(P("elevator", height=3), P("walljump_shaft", height=5), P("steps_down", k=3),
       TALK("c2_r10_talk"), hint="Turni sull'ascensore; poi Bubu sale tra le pareti scanalate fino alla leva."),
    _r(P("fragile_drop", depth=2), P("two_plates"), P("crate_ledge"), P("heavy_plate"),
       hint="Giù dalle assi, una piastra per lato, poi la cassa come gradino."),
    _r(P("heavy_crate_plate"), P("pulley", mem="m2_e"), P("gap", w=2.0),
       hint="Peso fisso sulla piastra; poi la carrucola per raggiungere la leva."),
    _r(P("moving_cross", span=8), P("walljump_shaft", height=7), P("boost_gate"),
       hint="Il traghetto vi aspetta; le pareti scanalate sono per Bubu; la leva alta col salto spinto.",
       intro="c2_r13_in"),
    _r(P("crate_ledge"), P("steps_down", k=2), P("elevator", height=4), P("steps_down", k=3),
       P("crate_plate_door"), P("cozy", dialogue="c2_cozy_b"),
       hint="Cassa come gradino, ascensore a turni, cassa piccola sulla piastra."),
]

# --- Chapter 3: Le nuvole --------------------------------------------------------------------
CH3 = [
    _r(S("c3_sign_bounce"), P("flat", n=2), P("bounce_up", height=3), P("steps_down", k=3), P("bounce_up", height=4),
       P("steps_down", k=2), P("flat", n=2), P("mystery_box", mem="m3_f"),
       hint="I funghi molleggiati vi lanciano in alto: saltateci sopra.",
       intro="c3_r01_in"),
    _r(S("c3_sign_seesaw"), P("seesaw", mem="m3_a"),
       hint="Altalena: chi pesa di più atterra su un'estremità e lancia l'altro dall'altra.", intro="c3_r02_in"),
    _r(S("c3_sign_vine"), P("vine_climb", height=4), P("steps_down", k=2), P("gap", w=2.0),
       P("vine_climb", height=5), P("steps_down", k=3), P("bounce_up", height=3), P("steps_down", k=3),
       hint="Sulle liane si sale con lo stick in su; A per staccarsi."),
    _r(S("c3_sign_timed"), P("timed_pair"), P("gap", w=1.5), P("seesaw"),
       hint="I pulsanti restano accesi pochi secondi: premeteli quasi insieme, uno a testa."),
    _r(S("c3_sign_wind"), P("wind_lift", height=5), P("steps_down", k=3), TALK("c3_r05_talk"),
       hint="Il ventilatore va finché qualcuno preme la piastra. Su in alto c'è una leva che lo tiene acceso.",
       intro="c3_r05_in"),
    _r(P("bounce_up", height=4), P("steps_down", k=2), P("seesaw"), P("timed_pair"),
       P("cozy", dialogue="c3_cozy_a", mem="m3_b"),
       hint="Fungo, poi altalena: Dudu atterra, Bubu vola."),
    _r(P("timed_pair"), P("vine_climb", height=5), P("steps_down", k=3), P("boost_memory", mem="m3_c"),
       hint="Pulsanti insieme; la liana; il ricordo è sopra la roccia."),
    _r(P("wind_lift", height=4), P("steps_down", k=2), P("seesaw"), TALK("c3_r08_talk"),
       hint="Vento, poi altalena."),
    _r(P("pulley"), P("bounce_up", height=4), P("steps_down", k=3), P("timed_pair"), P("vine_climb", height=4),
       P("steps_down", k=3),
       hint="Carrucola, fungo, pulsanti a tempo."),
    _r(P("vine_climb", height=4), P("steps_down", k=2), P("walljump_shaft", height=6, mem="m3_d"),
       P("wind_lift", height=4), P("steps_down", k=3),
       hint="Liana, pareti scanalate per Bubu, poi il vento.", intro="c3_r10_in"),
    _r(P("seesaw"), P("two_plates", bridge=True), P("bounce_up", height=3), P("steps_down", k=2),
       P("wind_lift", height=4), P("steps_down", k=3),
       hint="Altalena, ponte, fungo."),
    _r(P("timed_pair"), P("elevator", height=4), P("steps_down", k=2), P("wind_lift", height=4),
       P("steps_down", k=2), hint="Pulsanti, ascensore a turni, vento."),
    _r(P("bounce_up", height=4), P("steps_down", k=3), P("seesaw", mem="m3_e"), P("vine_climb", height=5),
       P("steps_down", k=3), TALK("c3_r13_talk"), hint="Fungo, altalena, liana."),
    _r(P("wind_lift", height=4), P("steps_down", k=2), P("timed_pair"), P("seesaw"),
       P("cozy", dialogue="c3_cozy_b"), hint="Vento, pulsanti a tempo, altalena. Poi un abbraccio.",
       intro="c3_r14_in"),
]

# --- Chapter 4: La notte ---------------------------------------------------------------------
CH4 = [
    _r(P("flat", n=2), P("boost_gate"), P("crate_ledge"), P("steps_down", k=2), P("bounce_up", height=3),
       P("steps_down", k=2), P("mystery_box", mem="m4_f"), hint="Tutto quello che avete imparato, di notte.", intro="c4_r01_in"),
    _r(S("c4_sign_launch"), P("seesaw", crate_launch=True, mem="m4_a"),
       hint="Stavolta vola Dudu: a Bubu serve qualcosa di pesante in braccio.", intro="c4_r02_in"),
    _r(P("heavy_crate_plate"), P("walljump_shaft", height=6), P("vine_climb", height=4), P("steps_down", k=3),
       P("timed_pair"),
       hint="Peso sulla piastra, pareti per Bubu, liana."),
    _r(P("pulley"), P("timed_pair"), P("fragile_drop", depth=3), TALK("c4_r04_talk"),
       hint="Carrucola, pulsanti insieme, poi giù dalle assi crepate."),
    _r(P("elevator", height=4), P("steps_down", k=2), P("seesaw", crate_launch=True),
       P("cozy", dialogue="c4_cozy_a", mem="m4_b"), hint="Ascensore a turni, poi lancio con la cassa."),
    _r(P("wind_lift", height=4), P("steps_down", k=2), P("crate_plate_door"), P("moving_cross", span=7),
       P("bounce_up", height=3), P("steps_down", k=3),
       hint="Vento, cassa sulla piastra, traghetto."),
    _r(P("two_plates", bridge=True), P("walljump_shaft", height=7, mem="m4_c"), P("bounce_up", height=4),
       P("steps_down", k=3), hint="Ponte, pareti scanalate, fungo.", intro="c4_r07_in"),
    _r(P("seesaw"), P("heavy_plate"), P("pulley"), TALK("c4_r08_talk"),
       hint="Altalena, piastra pesante insieme, carrucola."),
    _r(P("timed_pair"), P("crate_ledge"), P("steps_down", k=2), P("wind_lift", height=4), P("steps_down", k=3),
       hint="Pulsanti, cassa come gradino, vento."),
    _r(P("fragile_drop", depth=2), P("seesaw", crate_launch=True), P("vine_climb", height=5), P("steps_down", k=3),
       P("boost_memory", mem="m4_d"), hint="Assi crepate, lancio con la cassa, liana. Il ricordo è in alto."),
    _r(P("heavy_crate_plate"), P("elevator", height=4), P("steps_down", k=2), P("timed_pair"),
       hint="Peso sulla piastra, ascensore, pulsanti.", intro="c4_r11_in"),
    _r(P("moving_cross", span=8), P("pulley"), P("walljump_shaft", height=6), P("crate_ledge"),
       P("steps_down", k=3), P("cozy", required=False,
       dialogue="c4_cozy_b"), hint="Traghetto, carrucola, pareti."),
    _r(P("wind_lift", height=5), P("steps_down", k=3), P("seesaw"), P("crate_plate_door"), TALK("c4_r13_talk"),
       hint="Vento, altalena, cassa sulla piastra."),
    _r(P("boost_gate"), P("seesaw", crate_launch=True), P("timed_pair"), P("two_plates", bridge=True),
       P("cozy", dialogue="c4_cozy_c", mem="m4_e"),
       hint="Un po' di tutto. Alla fine, l'ultimo abbraccio.", intro="c4_r14_in"),
]

CHAPTERS = [
    dict(id="c1", title="Il prato", subtitle="", music="ch1", dialogue="res://data/dialogue/ch1.json",
         intro="c1_intro", outro="c1_outro", rooms=CH1),
    dict(id="c2", title="Il borgo", subtitle="", music="ch2", dialogue="res://data/dialogue/ch2.json",
         intro="c2_intro", outro="c2_outro", rooms=CH2),
    dict(id="c3", title="Le nuvole", subtitle="", music="ch3", dialogue="res://data/dialogue/ch3.json",
         intro="c3_intro", outro="c3_outro", rooms=CH3),
    dict(id="c4", title="La notte", subtitle="", music="ch4", dialogue="res://data/dialogue/ch4.json",
         intro="c4_intro", outro="c4_outro", rooms=CH4),
]


def build(root):
    """Writes every room; returns (chapters.json data, builders for checks)."""
    data, builders = [], []
    for ci, ch in enumerate(CHAPTERS):
        paths = []
        for ri, spec in enumerate(ch["rooms"]):
            path, b = build_room(root, ci + 1, ri, spec)
            paths.append(path)
            builders.append(b)
        entry = {k: v for k, v in ch.items() if k != "rooms"}
        entry["rooms"] = paths
        data.append(entry)
    return data, builders
