// outroMusic — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Outro music"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

samples({
  bd: ['bd/BT0AADA.wav','bd/BT0AAD0.wav','bd/BT0A0DA.wav','bd/BT0A0D3.wav','bd/BT0A0D0.wav','bd/BT0A0A7.wav'],
  sd: ['sd/rytm-01-classic.wav','sd/rytm-00-hard.wav'],
  hh: ['hh27/000_hh27closedhh.wav','hh/000_hh3closedhh.wav'],
  perc: ['perc/002_perc2.wav'],
}, 'github:tidalcycles/dirt-samples');

chord("<C^7 Am7 Dm7 G7>*2").dict('lefthand').anchor("G4").voicing()
  .stack(n("0@6 [<1 2> <2 0> 1]@2").scale('C5 major'))
  .slow(4)
  .s("gm_epiano1:1")
  .color('steelblue')
  .stack(
   "<-7 ~@2 [~@2 -7] -9 ~@2 [~@2 -9] -10!2 ~ [~@2 -10] -5 ~ [-3 -2 -10]@2>*2"
    .scale('C3 major').note()
    .s('sawtooth').color('brown')
  )
  .attack(0.05).decay(.1).sustain(.7)
  .cutoff(perlin.range(800,2000))
  .gain(.3)
  .stack(
    s("<bd!3 [bd ~ bd]> sd,hh*3,~@5 <perc perc*3>")
    .speed(perlin.range(.9,1.1))
    .n(3).color('gray')
  ).slow(3/2)
  //.pianoroll({autorange:1,vertical:1,fold:0})
