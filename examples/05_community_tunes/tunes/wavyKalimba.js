// wavyKalimba — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Wavy kalimba"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

setcps(1)

samples({
  'kalimba': { c5:'https://cdn.freesound.org/previews/536/536549_11935698-lq.mp3' }
})
const scales = "<C:major C:mixolydian F:lydian [F:minor Db:major]>"

stack(
  "[0 2 4 6 9 2 0 -2]*3"
  .add("<0 2>/4")
  .scale(scales)
  .struct("x*8")
  .velocity("<.8 .3 .6>*8")
  .slow(2),
  "<c2 c2 f2 [[F2 C2] db2]>"
  .scale(scales)
  .scaleTranspose("[0 <2 4>]*2")
  .struct("x*4")
  .velocity("<.8 .5>*4")
  .velocity(0.8)
  .slow(2)
)
  .fast(1)
  .note()
  .clip("<.4 .8 1 1.2 1.4 1.6 1.8 2>/8")
  .s('kalimba')
  .delay(.2)
