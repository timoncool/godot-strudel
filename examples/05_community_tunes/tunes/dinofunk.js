// dinofunk — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Dinofunk"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

setcps(1)

samples({bass:'https://cdn.freesound.org/previews/614/614637_2434927-hq.mp3',
dino:{b4:'https://cdn.freesound.org/previews/316/316403_5123851-hq.mp3'}})
setVoicingRange('lefthand', ['c3','a4'])

stack(
s('bass').loopAt(8).clip(1),
s("bd*2, ~ sd,hh*4"),
chord("Abm7")
  .mode("below:G4")
  .dict('lefthand')
  .voicing()
  .struct("x(3,8,1)".slow(2)),
"0 1 2 3".scale('ab4 minor pentatonic')
.superimpose(x=>x.add(.1))
.sometimes(x=>x.add(12))
.note().s('sawtooth')
.cutoff(sine.range(400,2000).slow(16)).gain(.8)
.decay(perlin.range(.05,.2)).sustain(0)
.delay(sine.range(0,.5).slow(32))
.degradeBy(.4).room(1),
note("<b4 eb4>").s('dino').delay(.8).slow(8).room(.5)
)
