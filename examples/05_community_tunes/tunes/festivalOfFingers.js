// festivalOfFingers — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Festival of fingers"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

const chords = "<Cm7 Fm7 G7 F#7>";
stack(
  chord(chords).dict('lefthand').voicing()
  .struct("x(3,8,-1)")
  .gain(.5).off(1/7,x=>x.add(note(12)).mul(gain(.2))),
  chords.rootNotes(2).struct("x(4,8,-2)").note(),
  chords.rootNotes(4)
  .scale(cat('C minor','F dorian','G dorian','F# mixolydian'))
  .struct("x(3,8,-2)".fast(2))
  .scaleTranspose("0 4 0 6".early(".125 .5"))
  .layer(scaleTranspose("0,<2 [4,6] [5,7]>/4"))
  .note()
).slow(2)
 .mul(gain(sine.struct("x*8").add(3/5).mul(2/5).fast(8)))
 .piano()
