// @title Кувшинка · lofi
// Настоящий трек на Strudel: стек партий, форма из шестнадцати секций,
// аккордовый круг, свинг, вероятностное прореживание, эффекты.
//
// Этот файл — главная приёмка плагина: он играет в Godot целиком, от начала
// до конца, теми же нотами, что в Strudel. Вставлен БЕЗ ЕДИНОЙ ПРАВКИ.

setcpm(76/4)

const sw = x => x.swingBy(0.23, 4)
const dB = d => Math.pow(10, d / 20)

const P  = "<C^7 Am7 F^7 G7 Dm7 G7 Em7 Am7>"
const ch = chord(P)

// ═══ core ═══ bass: root(0) fifth(6) third(10) approach(14), oct -1
const bass = stack(
  n("0").set(ch).mode("root:c2").voicing().struct("x ~ ~ ~ ~ ~ ~ ~").gain(dB(-13)),
  n("2").set(ch).mode("root:c2").voicing().struct("~ ~ ~ x ~ ~ ~ ~").gain(dB(-19)).degradeBy(0.25),
  n("1").set(ch).mode("root:c2").voicing().struct("~ ~ ~ ~ ~ x ~ ~").gain(dB(-17)),
  // ВНИМАНИЕ: здесь НЕ должно быть лишнего .note() — rootNotes уже отдаёт
  // {note: "C2"}, и повторный .note() вкладывает значение само в себя
  // ({note:{note:"C2"}}), после чего .add() бросает "cannot parse as numeral".
  // queryArc глотает исключение, и молчит ВЕСЬ трек, а не одна партия.
  ch.rootNotes(2).add(note(11)).struct("~ ~ ~ ~ ~ ~ ~ x").gain(dB(-20)).degradeBy(0.3)
).s("contrabass").clip(0.9).lpf(600)

// ep: аккорд 2 ноты от 1-й ступени, at [3,11]
const ep = n("1 2").set(ch).mode("above:c4").voicing().s("piano")
  .struct("~ ~ ~ x ~ ~ ~ ~ ~ ~ ~ x ~ ~ ~ ~")
  .clip(1.3).gain(dB(-21)).room(0.5).pan(0.5)

// ═══ drums ═══
const drums = stack(
  s("<[bd ~ ~ ~ ~ bd ~ ~] [bd ~ ~ bd ~ bd ~ ~] [bd ~ ~ ~ ~ bd ~ bd] [bd ~ ~ bd ~ ~ ~ ~]>")
    .bank("RolandTR909").gain(dB(-11)).lpf(260),
  s("~ ~ sd ~ ~ ~ sd ~").bank("RolandTR909").gain(dB(-19)).pan(0.2),
  s("~ ~ ~ sd ~ ~ ~ sd").bank("RolandTR909").gain(dB(-30))
    .degradeBy(0.3).speed(1.06).pan(0.35),
  s("shaker*8").gain("0.018 0.0106 0.0106 0.0106 0.0316 0.0106 0.0106 0.0106")
    .speed(perlin.range(0.97, 1.05)).pan(sine.range(0.32, 0.68))
)

// ═══ arp ═══ harp [1,9] oct -1
const arp = n("<0 1 2 3>").set(ch).mode("above:c3").voicing().s("harp")
  .struct("~ x ~ ~ ~ ~ ~ ~ ~ x ~ ~ ~ ~ ~ ~")
  .clip(1.5).gain(dB(-29)).room(0.6).delay(0.2).pan(0.5).degradeBy(0.25)

// ═══ lift ═══ harp [2,6,10,14] oct 0
const lift = n("<0 1 2 3>").set(ch).mode("above:c4").voicing().s("harp")
  .struct("~ x ~ x ~ x ~ x").clip(1.4).gain(dB(-28)).room(0.6).pan(0.45).degradeBy(0.3)

// ═══ bridge ═══ ep аккорд 3 ноты [0,8]
const bridge = n("0 1 2").set(ch).mode("above:c4").voicing().s("piano")
  .struct("x ~ ~ ~ ~ ~ ~ ~ x ~ ~ ~ ~ ~ ~ ~").clip(1.8).gain(dB(-22)).room(0.55)

// ═══ hook ═══ lead: аккорд [4,12] oct+1 · риф turn [0,2,1,0,0,2,3,1]
const hookChord = n("2 3").set(ch).mode("above:c5").voicing().s("horn")
  .struct("~ ~ x ~ ~ ~ x ~").attack(0.3).release(1.2)
  .gain(dB(-30)).lpf(1200).room(0.7).pan(0.5).degradeBy(0.25)

const riff = n("<[0 2 1 0] [0 2 3 1]>").set(ch).mode("above:c4").voicing().s("horn")
  .struct("x ~ ~ x ~ x ~ x").attack(0.25).release(1.0)
  .gain(dB(-25)).lpf(1300).room(0.65).pan(0.2)

// ═══ pad (viola) и glow (vibraphone) ═══
const pad = n("0 1 2").set(ch).mode("above:c3").voicing().s("viola")
  .attack(1.5).release(2.4).lpf(1000).gain(dB(-20)).room(0.8)

const glow = n("<0 2>").set(ch).mode("above:c5").voicing().s("vibraphone")
  .struct("x ~ ~ ~ ~ ~ ~ ~ x ~ ~ ~ ~ ~ ~ ~").clip(1.6)
  .gain(dB(-30)).room(0.7).pan(0.6).degradeBy(0.7)

// ═══ ФОРМА — forms[0]: [0,1,1,4,2,2,1,3,1,4,2,7,1,1,2,6] ═══
const S0 = sw(stack(bass, ep, pad.gain(dB(-19))))
const S1 = sw(stack(bass, ep, drums, pad.gain(dB(-22))))
const S2 = sw(stack(bass, ep, drums, arp, hookChord, pad.gain(dB(-23))))
const S3 = sw(stack(bass, ep, arp, pad.gain(dB(-17))))
const S4 = sw(stack(bass, ep, drums, arp, lift, pad.gain(dB(-21))))
const S5 = sw(stack(bass, ep, bridge, pad.gain(dB(-16))))
const S6 = sw(stack(bass, ep, drums, arp, lift, riff, glow, pad.gain(dB(-20))))
const S7 = sw(stack(bass, ep, drums, riff, hookChord, pad.gain(dB(-21))))

$: arrange(
  [4, S0._scope()], [4, S1._scope()], [4, S1._scope()], [4, S4._scope()],
  [4, S2._scope()], [4, S2._scope()], [4, S1._scope()], [4, S3._scope()],
  [4, S2._scope()], [4, S2._scope()], [4, S1._scope()], [4, S7._scope()],
  [4, S1._scope()], [4, S1._scope()], [4, S2._scope()], [4, S6._scope()]
)
