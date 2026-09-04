// echoPiano — трек из коллекции Strudel (website/src/repl/tunes.mjs).
// Взят КАК ЕСТЬ, без единой правки: на таких треках и проверяется плагин.

// "Echo piano"
// @license CC BY-NC-SA 4.0 https://creativecommons.org/licenses/by-nc-sa/4.0/
// @by Felix Roos

n("<0 2 [4 6](3,4,2) 3*2>").color('salmon')
.off(1/4, x=>x.add(n(2)).color('green'))
.off(1/2, x=>x.add(n(6)).color('steelblue'))
.scale('D minor')
.echo(4, 1/8, .5)
.clip(.5)
.piano()
.pianoroll()
