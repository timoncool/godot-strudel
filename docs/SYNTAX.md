# Что из Strudel работает в Godot

Справочник по поддержке. Три состояния: **есть** (сверено с Булкой),
**есть, но иначе** (работает, отличие названо), **нет** (не перенесено).

Если чего-то нет в этом списке и оно не работает — это не баг, а пробел;
если оно есть в списке и не работает — баг, и о нём стоит написать.

---

## Код целиком

Плагин исполняет не только выражения, но и программу: объявления, стрелочные
функции, метки вывода.

| запись | состояние |
|---|---|
| `const x = …`, `let`, `var` | есть |
| `x => x.gain(0.5)`, `(a, b) => …` | есть |
| `$: паттерн` — вывод | есть |
| `имя: паттерн` — именованный вывод | есть, все выводы складываются `stack` |
| несколько выводов в одном файле | есть |
| цепочки через точку | есть |
| `[1, 2]`, `{a: 1}` | есть |
| арифметика `+ - * / %`, сравнения, `&& || ??` | есть |
| `Math.pow`, `Math.floor`, `Math.min`… | есть |
| `// строчный` и `/* блочный */` комментарии | есть |
| `setcpm(…)`, `setcps(…)` | есть |
| шаблонные строки с `${…}` | есть: вставки считаются ДО mini-нотации |
| `import`, `for`, `if`, `function`, классы | **нет** — в паттернах Strudel не встречаются |

Ошибка разбора всегда несёт **строку и место**, а не молчание:

```
Strudel: строка 4: ожидал ")"
Strudel: в строке "bd [sd": не закрыта скобка "[" (позиция 3)
```

---

## Mini-нотация

Перенесена целиком по грамматике `krill.pegjs`.

| запись | что делает | состояние |
|---|---|---|
| `bd sd hh` | последовательность | есть |
| `~`, `-` | пауза | есть |
| `[bd sd]` | группа | есть |
| `<bd sd>` | по одному за цикл | есть |
| `bd, hh*4` | слои | есть |
| `{bd sd, hh hh hh}` | полиметр | есть |
| `{…}%4` | полиметр с числом шагов | есть |
| `bd*4`, `bd/2` | уплотнение и разрежение | есть |
| `bd!3`, `bd!!` | повтор | есть |
| `bd@3`, `bd _ _` | вес доли | есть |
| `bd:3` | индекс сэмпла | есть |
| `bd(3,8)`, `bd(3,8,2)` | эвклидов ритм со сдвигом | есть |
| `bd?`, `bd?0.3` | вероятностный пропуск | есть, смещение случайного как в оригинале |
| `bd | sd | hh` | случайный выбор на цикл | есть |
| `bd sd . hh hh hh` | стопы | есть |
| `0 .. 7` | диапазон | есть |
| вложенность любой глубины | | есть |

---

## Комбинаторы и время

| функция | состояние |
|---|---|
| `stack`, `cat`, `slowcat`, `fastcat`, `sequence`, `seq` | есть |
| `timeCat`, `stepcat`, `arrange` | есть |
| `polymeter`, `pm` | есть |
| `superimpose`, `layer`, `apply`, `applyN` | есть |
| `fast`, `slow`, `density`, `sparsity`, `hurry` | есть |
| `early`, `late`, `rev`, `revv`, `palindrome` | есть |
| `iter`, `iterBack`, `ply`, `press`, `pressBy` | есть |
| `off`, `jux`, `juxBy`, `echo`, `echoWith`, `stut` | есть |
| `struct`, `structAll`, `mask`, `maskAll` | есть |
| `segment`, `seg`, `compress`, `zoom`, `focus`, `linger` | есть |
| `fastGap`, `striate`, `chop` | есть |
| `every`, `firstOf`, `lastOf`, `when`, `chunk`, `chunkBack` | есть |
| `inside`, `outside`, `within`, `filter`, `filterWhen` | есть |
| `swingBy`, `swing` | есть |
| `repeatCycles`, `ribbon`, `rib` | есть |
| `pace`, `steps`, `expand`, `contract`, `extend` | есть |
| `slice`, `splice`, `fit`, `loopAt`, `bite` | есть |
| `take`, `drop`, `grow`, `shrink`, `tour`, `zip`, `stepJoin` | есть |
| `pick`, `pickmod`, `pickOut`, `pickRestart`, `pickReset`, `inhabit`, `pickF` | есть |
| `chunkInto`, `chunkBackInto`, `fastChunk`, `slowChunk`, `into`, `unjoin` | есть |
| `plyWith`, `plyForEach`, `juxFlip`, `juxFlipBy`, `echoWith`, `collect` | есть |

Все аргументы **патернифицированы**, как в оригинале: `fast("<1 2 3>")`
работает, скорость меняется по циклам.

---

## Сигналы и случайное

| функция | состояние |
|---|---|
| `sine`, `cosine`, `saw`, `isaw`, `tri`, `itri`, `square`, `isquare` | есть |
| двуполярные варианты (`sine2`, `saw2`…) | есть |
| `perlin`, `time` | есть |
| `rand`, `rand2`, `irand`, `brand`, `brandBy` | есть, бит в бит |
| `.range()`, `.rangex()`, `.range2()` | есть |
| `run`, `choose`, `chooseCycles`, `randcat`, `chooseWith` | есть |
| `degradeBy`, `degrade`, `undegradeBy`, `undegrade` | есть |
| `sometimesBy`, `sometimes`, `often`, `rarely`, `almostNever`, `almostAlways` | есть |
| `someCyclesBy`, `someCycles`, `shuffle`, `scramble`, `seed` | есть |
| `berlin`, `wchoose`, `wchooseCycles`, `randL`, `randrun` | есть |
| `binary`, `binaryN`, `binaryL`, `binaryNL` | есть |
| `useRNG('precise')` | есть; по умолчанию, как и в Strudel, `legacy` |

---

## Тональное

| функция | состояние |
|---|---|
| `note("c3 e3")`, имена нот с диезами и октавами | есть |
| `n("0 2 4")` | есть |
| `chord("<C^7 Am7>")` | есть |
| `voicing()` | есть, раскладки `ireal` и `ireal-ext` |
| `mode("root:c2")`, `mode("above:c4")` | есть, режимы below/above/root/duck |
| `rootNotes(2)` | есть |
| `scale("C:major")` | есть, 92 лада из @tonaljs |
| `transpose(5)` | есть, имена нот сохраняются (`c3` + 5 = `F3`) |
| `arp("0 1")`, `arpWith` | есть |
| `scaleTranspose`, `voicings`, `chord`, `voicing` | есть |
| словари раскладок `ireal`, `ireal-ext`, `lefthand`, `guidetones`, `triads`, `legacy` | есть |

Раскладки и лады **порождены из исходников Булки** (`tools/gen_voicings.py`,
`tools/gen_scales.py`), а не переписаны руками.

---

## Звук

### Источники

| что | состояние |
|---|---|
| `sine`, `sawtooth`, `square`, `triangle` | есть, **ограниченные по полосе**, как в WebAudio |
| `white`, `pink`, `brown` | есть |
| сэмплы из папки пользователя | есть: WAV (8 и 16 бит), ogg, mp3 |
| карты формата Strudel (`_base`, списки, многосэмплированные) | есть |
| `:n` — индекс, `.bank("…")` — набор | есть |
| саундфонты `sf:банк:программа` | есть, `.sf2`, загрузка ленивая |
| FM — полная матрица восьми голосов (`fmi`, `fmh`, `fmwave`, `fmenv`, огибающие) | есть, сверено 0.00 дБ |
| `supersaw` (`unison`, `detune`, `spread`) | есть |
| своя волна: `partials`, `phases` | есть, сверено 0.00 дБ |
| огибающая высоты (`penv`, `pattack`…, `panchor`) и вибрато (`vib`, `vibmod`) | есть |

**Пустой банк — штатное состояние.** Если сэмплов нет, всё играет синтезом,
а в лог уходит понятное предупреждение.

### Эффекты

| параметр | состояние |
|---|---|
| `gain`, `postgain`, `velocity` | есть, сверено 0.00 дБ |
| `attack`, `decay`, `sustain`, `release`, `clip` | есть, сверено 0.00 дБ |
| `pan` | есть, **на голос**, сверено 0.00 дБ |
| `lpf`/`cutoff`, `lpq`/`resonance` | есть |
| `hpf`/`hcutoff`, `hpq` | есть |
| `bpf`/`bandf`, `bpq`/`bandq` | есть |
| `vowel` | есть, все 15 гласных плюс диакритика |
| `crush`, `coarse`, `shape` | есть, сверено 0.00 дБ |
| `speed` | есть |
| `room`, `roomsize`, `roomfade`, `roomlp`, `roomdim` | есть, **другое устройство хвоста** (Шрёдер вместо свёртки) |
| `delay`, `delaytime`, `delaysync`, `delayfeedback` | есть, линия **на орбиту** |
| `orbit` | есть: у каждой орбиты свои эхо и зал |
| `distort` со всеми девятью кривыми, `distortvol`, `distorttype` | есть, сверено 0.00 дБ |
| `tremolo`, `tremolosync`, `tremolodepth`, `tremoloskew`, `tremoloshape` | есть |
| `compressor` и его настройки | есть, уровень сверен |
| `phaser`, `phaserdepth`, `phasercenter`, `phasersweep` | есть |
| огибающие фильтров (`lpenv`, `lpattack`…, `fanchor`) для НЧ, ВЧ и полосового | есть, сверено 0.00 дБ |
| модуляция `lfo`, `env`, `bmod` | описание кладётся в событие |

Порядок цепи — тот же, что в `superdough`; подробности и числа в
[COMPARISON.md](COMPARISON.md).

### Умолчания

Взяты из `superdough.mjs:185`, а не назначены на глаз:

| параметр | значение |
|---|---|
| `s` | `triangle` |
| `gain` | `0.8` |
| `postgain`, `velocity` | `1` |
| `release` | `0.01` |
| ADSR сэмплера | `[0.001, 0.001, 1, 0.01]` |
| ADSR синтеза | `[0.001, 0.05, 0.6, 0.01]` |
| приглушение синтеза | `0.3` (`synth.mjs:54`) |

---

## Отличия, о которых надо знать заранее

1. **Сети нет.** Strudel тянет сэмплы по ссылкам; плагин берёт только локальные
   файлы. `_base`, указывающий на адрес, считается пустым.
2. **Только WAV.** Godot не отдаёт PCM из ogg и mp3 в GDScript. Пак переводится
   заранее.
3. **Лимитера нет** — как и в Strudel. Перегруз считается и о нём предупреждают;
   мягкое ограничение включается отдельно (`master_limiter`).
4. **Имена функций сохранены как в Strudel** (`degradeBy`, а не `degrade_by`) —
   иначе чужой код перестал бы вставляться без правок. Godot-стиль
   (`snake_case`) живёт в программном API на классе `StrudelPattern`.
