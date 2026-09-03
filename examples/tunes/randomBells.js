// randomBells — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Random bells"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

samples({
  bell: { c6: 'https://cdn.freesound.org/previews/411/411089_5121236-lq.mp3' },
  bass: { d2: 'https://cdn.freesound.org/previews/608/608286_13074022-lq.mp3' }
})

stack(
  // bells
  n("0").euclidLegato(3,8)
  .echo(3, 1/16, .5)
  .add(n(rand.range(0,12)))
  .scale("D:minor:pentatonic")
  .velocity(rand.range(.5,1))
  .s('bell').gain(.6).delay(.2).delaytime(1/3).delayfeedback(.8),
  // bass
  note("<D2 A2 G2 F2>").euclidLegatoRot(6,8,4).s('bass').clip(1).gain(.8)
)
  .slow(6)
  .pianoroll({vertical:1})
