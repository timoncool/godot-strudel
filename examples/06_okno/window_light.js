// @title Пока горит окно
// @by Nerual Dreming & Claude
// E minor · только фортепиано · 84 BPM

// Hydra-визуал Булки отрезан: в игре своя картинка (акварель).
// Музыка ниже — дословно как в Булке.

setcpm(84/4)

const HALL_LEAD = (p) => LEAD_AHEAD(GLUE_LEAD(p)).orbit(1).roomsize(4.5).roomlp(5200).roomdim(0.3).roomfade(1.9)
const HALL_LOW  = (p) => GLUE_LOW(p).orbit(2).roomsize(2.2).roomlp(1900).roomdim(0.5).roomfade(0.9)
const HALL_FAR  = (p) => p.orbit(3).roomsize(6).roomlp(3800).roomdim(0.4).roomfade(3.2)
const FAR_DELAY = (p) => p.delay(0.16).delaytime(0.375).delayfeedback(0.24)

const GLUE_LOW  = (p) => p.compressor("-26:4:9:.01:.12").shape(0.16).postgain(1.12).hpf(38)
const GLUE_LEAD = (p) => p.compressor("-20:3:10:.006:.18").shape(0.1).postgain(1.06)

const LEAD_AHEAD = (p) => p.early(0.009)

const themeA = HALL_LEAD(note("<[~ b4 e5 f#5 g5 ~ e5 ~] [d5 ~ c5 ~ b4 g4 ~ ~] [~ b4 e5 f#5 g5 b5 a5 g5] [f#5 ~ e5 d5 ~ b4 ~ ~] [~ b4 e5 f#5 g5 ~ b5 ~] [a5 ~ g5 e5 d5 ~ c5 ~] [~ c5 e5 a5 g5 f#5 d#5 ~] [b4 ~ d#5 f#5 ~ e5 ~ ~]>")
  .s("piano").gain(0.98).clip(1.9).hpf(180).room(0.25).pan(0.56))

const themeA2 = HALL_LEAD(note("<[~ b4 e5 f#5 g5 ~ e5 ~] [d5 ~ c5 ~ b4 g4 ~ ~] [~ b4 e5 f#5 g5 b5 a5 g5] [f#5 ~ e5 d5 ~ b4 ~ ~] [~ b4 e5 f#5 g5 b5 d6 ~] [c6 ~ b5 g5 e5 ~ d5 ~] [~ c5 e5 a5 c6 b5 a5 f#5] [d#5 ~ f#5 a5 b5 f#5 d#5 ~]>")
  .s("piano").gain(1).clip(1.9).hpf(180).room(0.27).pan(0.56))

const themeB = HALL_LEAD(note("<[~ g4 c5 e5 g5 ~ e5 ~] [d5 ~ b4 ~ a4 b4 ~ ~] [~ a4 d5 f#5 a5 ~ f#5 ~] [g5 ~ e5 b4 ~ ~ ~ ~] [~ g4 c5 e5 g5 a5 b5 ~] [c6 ~ a5 e5 c5 ~ b4 ~] [~ f#5 a5 c6 b5 a5 f#5 d#5] [b4 ~ d#5 f#5 ~ ~ ~ ~]>")
  .s("piano").gain(0.98).clip(1.9).hpf(180).room(0.27).pan(0.56))

const releaseTheme = HALL_LEAD(note("<[~ b4 e5 f#5 g5 ~ e5 ~] [~ g4 c5 d5 e5 ~ c5 ~] [~ b4 d#5 f#5 a5 ~ f#5 ~] [g5 ~ f#5 ~ e5 ~ ~ ~]>")
  .s("piano").gain(0.92).clip(1.7).hpf(180).lpf(3300).room(0.34).pan(0.57))

const bridgeSequence = HALL_LEAD(note("<[~ g4 c5 d5 e5 ~ c5 ~] [~ e4 a4 b4 c5 ~ a4 ~] [~ b4 e5 f#5 g5 ~ e5 ~] [b4 ~ d#5 ~ f#5 ~ a5 b5]>")
  .s("piano").gain(0.9).clip(1.6).hpf(180).room(0.34).pan(0.56))

const codaTheme = HALL_LEAD(note("<[~ b4 e5 f#5 g5 ~ ~ ~] [e5 ~ d5 c5 b4 ~ ~ ~] [~ b4 d#5 f#5 a5 ~ f#5 ~] [e5 ~ b4 ~ e5 ~ ~ ~]>")
  .s("piano").gain(0.8).clip(2).hpf(180).room(0.44).pan(0.55))

const leftHandA4 = HALL_LOW(note("<[e2 b2 e3 g3] [c2 g2 c3 e3] [b1 d2 g2 b2] [d2 a2 d3 f#3] [e2 b2 e3 g3] [c2 g2 c3 e3] [a1 e2 a2 c3] [b1 f#2 a2 d#3]>")
  .s("piano").gain("0.22 0.14 0.18 0.13").clip(1.45).lpf(1450).room(0.34).pan(0.31))

const leftHandA8 = HALL_LOW(note("<[e2 b2 e3 g3 b3 g3 e3 b2] [c2 g2 c3 e3 g3 e3 c3 g2] [b1 d2 g2 b2 d3 b2 g2 d2] [d2 a2 d3 f#3 a3 f#3 d3 a2] [e2 b2 e3 g3 b3 g3 e3 b2] [c2 g2 c3 e3 g3 e3 c3 g2] [a1 e2 a2 c3 e3 c3 a2 e2] [b1 f#2 b2 d#3 f#3 d#3 a2 f#2]>")
  .s("piano").gain("0.24 0.14 0.19 0.13 0.21 0.13 0.18 0.12").clip(1.35).lpf(1550).room(0.36).pan(0.3))

const leftHandB8 = HALL_LOW(note("<[c2 g2 c3 e3 g3 e3 c3 g2] [b1 d2 g2 b2 d3 b2 g2 d2] [d2 a2 d3 f#3 a3 f#3 d3 a2] [e2 b2 e3 g3 b3 g3 e3 b2] [c2 g2 c3 e3 g3 e3 c3 g2] [a1 e2 a2 c3 e3 c3 a2 e2] [b1 f#2 b2 d#3 f#3 d#3 a2 f#2] [b1 f#2 a2 d#3 f#3 a3 f#3 d#3]>")
  .s("piano").gain("0.24 0.14 0.19 0.13 0.21 0.13 0.18 0.12").clip(1.35).lpf(1550).room(0.36).pan(0.3))

const leftHandBridge8 = HALL_LOW(note("<[c2 g2 c3 e3 g3 e3 c3 g2] [a1 e2 a2 c3 e3 c3 a2 e2] [e2 b2 e3 g3 b3 g3 e3 b2] [b1 f#2 b2 d#3 f#3 a3 f#3 d#3]>")
  .s("piano").gain("0.24 0.14 0.19 0.13 0.22 0.14 0.19 0.13").clip(1.35).lpf(1550).room(0.38).pan(0.29))

const leftHandCoda4 = HALL_LOW(note("<[e2 b2 e3 g3] [c2 g2 c3 e3] [b1 f#2 a2 d#3] [e2 b2 e3 g#3]>")
  .s("piano").gain("0.18 0.11 0.15 0.1").clip(1.5).lpf(1250).room(0.5).pan(0.32))

const releaseBass = HALL_LOW(note("<[e2 ~ b1 e2 g2 ~ f#2 e2] [c2 ~ g1 c2 e2 ~ d2 c2] [b1 ~ f#2 b2 d#3 ~ a2 f#2] [e2 b1 e2 g2 b2 g2 f#2 e2]>")
  .s("piano").gain("0.2 0.1 0.15 0.12 0.17 0.1 0.14 0.11").clip(1.4).lpf(1200).room(0.34).pan(0.4))

const bassOctavesA = HALL_LOW(note("<[e1 ~ ~ ~ e2 ~ ~ ~] [c1 ~ ~ ~ c2 ~ ~ ~] [g0 ~ ~ ~ g1 ~ ~ ~] [d1 ~ ~ ~ d2 ~ ~ ~] [e1 ~ ~ ~ e2 ~ ~ ~] [c1 ~ ~ ~ c2 ~ ~ ~] [a0 ~ ~ ~ a1 ~ ~ ~] [b0 ~ ~ b1 ~ b0 ~ b1 ~]>")
  .s("piano").gain(0.3).clip(2.2).lpf(420).room(0.26).pan(0.5))

const pianoAnswerA = FAR_DELAY(HALL_FAR(note("<[~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ e4 f#4] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ a3 b3] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ ~ e4] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ f#4 b4]>")
  .s("piano").gain(0.23).clip(1.4).hpf(170).lpf(2600).room(0.46).pan(0.38)))

const pianoAnswerB = FAR_DELAY(HALL_FAR(note("<[~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ g4 a4] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ b3 d4 e4] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ ~ ~ e4] [~ ~ ~ ~ ~ ~ ~ ~] [~ ~ ~ ~ ~ a3 b3 d#4]>")
  .s("piano").gain(0.22).clip(1.4).hpf(170).lpf(2550).room(0.46).pan(0.37)))

const chordsA = HALL_FAR(n("0").chord("<Em C G D Em C Am B7>").voicing()
  .struct("x ~ ~ ~ ~ ~ ~ ~")
  .s("piano").gain(0.12).clip(1.7).lpf(1050).room(0.4).pan(0.44))

$: arrange(
  [4, themeA.pan(0.52).gain(0.94)._scope()],

  [8, stack(
    leftHandA4,
    pianoAnswerA.gain(0.16),
    themeA
  )._scope()],

  [8, stack(
    leftHandA8,
    chordsA.gain(0.09),
    pianoAnswerA.gain(0.21),
    themeA2
  )._scope()],

  [8, stack(
    leftHandB8,
    chordsA.gain(0.1),
    pianoAnswerB.gain(0.22),
    themeB
  )._scope()],

  [4, stack(
    leftHandBridge8,
    pianoAnswerB.gain(0.18),
    bridgeSequence
  )._scope()],

  [8, stack(
    bassOctavesA,
    themeA2.add(note(-24)).gain(0.2).clip(1.5).hpf(45).lpf(1750).room(0.18).pan(0.42),
    leftHandA8.gain("0.26 0.15 0.21 0.14 0.23 0.14 0.2 0.13").room(0.26).lpf(2500),
    pianoAnswerA.gain(0.22).room(0.34),
    themeA2.gain(1.12).room(0.18)
  )._scope()],

  [8, stack(
    bassOctavesA.gain(0.33),
    leftHandA8.gain("0.26 0.15 0.21 0.14 0.23 0.14 0.19 0.13").room(0.24).lpf(2700),
    pianoAnswerA.gain(0.2).room(0.32),
    themeA2.gain(1.12).room(0.16)
  )._scope()],

  [4, stack(
    releaseBass,
    releaseTheme
  )._scope()],

  [8, stack(
    leftHandA8.gain("0.2 0.12 0.16 0.11 0.18 0.11 0.15 0.1").room(0.38),
    chordsA.gain(0.08),
    pianoAnswerA.gain(0.175).room(0.5),
    themeA.gain(0.93).room(0.34)
  )._scope()],

  [8, stack(
    leftHandA4.gain("0.17 0.1 0.14 0.09").room(0.42).lpf(1150),
    pianoAnswerA.gain(0.135).room(0.54),
    themeA.gain(0.84).room(0.4)
  )._scope()],

  [4, stack(
    leftHandCoda4,
    codaTheme
  )._scope()]
)
