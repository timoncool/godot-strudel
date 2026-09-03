// Снятие эталона с ЖИВОЙ Булки: 32 трека сообщества, восемь кругов каждый.
//
// Порядок:
//   1. python tools/judge/receiver.py 4199
//   2. открыть Булку (http://127.0.0.1:4188), КЛИКНУТЬ по странице —
//      без жеста пользователя звуковой контекст не поднимается, и
//      repl.evaluate висит на инициализации навсегда;
//   3. вставить этот файл в консоль страницы.
//
// Кладёт tools/judge/golden/tunes_haps.json и ВОЗВРАЩАЕТ редактору
// прежний код: снятие эталона не должно стирать работу игрока.
window.__savedCode = window.strudelMirror.code;
window.__cap = { done: false, step: 'старт', out: {} };
(async () => {
  const fr = (f) => `${f.s < 0 ? '-' : ''}${f.n}/${f.d}`;
  const list = await (await fetch('http://127.0.0.1:4199/tunes')).json();
  for (const t of list) {
    window.__cap.step = t.id;
    try {
      // 🔴 Код надо ПОЛОЖИТЬ В РЕДАКТОР, а не только скормить repl.
      // Подсветка mini-мест меряется по документу редактора, и на треке
      // длиннее прежнего Булка падает «Position N is out of range for
      // changeset of length M», отдавая silence. Так festivalOfFingers
      // выходил пустым — и это была беда снималки, а не движка.
      window.strudelMirror.setCode(t.code);
      // Второй довод false — не запускать воспроизведение: нужен только разбор.
      await window.strudelMirror.repl.evaluate(t.code, false);
      const haps = window.strudelMirror.repl.state.pattern.queryArc(0, 8);
      window.__cap.out[t.id] = {
        n: haps.length,
        to: 8,
        haps: haps.map((h) => [
          h.whole ? fr(h.whole.begin) : '',
          h.whole ? fr(h.whole.end) : '',
          fr(h.part.begin),
          fr(h.part.end),
          h.value,
        ]),
      };
    } catch (e) {
      window.__cap.out[t.id] = { error: String(e) };
    }
  }
  await fetch('http://127.0.0.1:4199/tunes_haps', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(window.__cap.out),
  });
  window.strudelMirror.setCode(window.__savedCode);
  await window.strudelMirror.repl.evaluate(window.__savedCode, false);
  window.__cap.done = true;
})();
