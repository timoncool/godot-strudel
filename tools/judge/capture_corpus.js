// Снятие эталона СОБЫТИЙ по корпусу выражений (`corpus.json`).
//
// Порядок как у capture_tunes.js: поднять приёмник, открыть Булку, кликнуть
// по странице, вставить это в консоль. Кладёт golden/haps.json.
window.__savedCode = window.strudelMirror.code;
window.__cap = { done: false, step: 'старт', out: {}, errors: [] };
(async () => {
  const fr = (f) => `${f.s < 0 ? '-' : ''}${f.n}/${f.d}`;
  const list = await (await fetch('http://127.0.0.1:4199/corpus')).json();
  for (const item of list) {
    window.__cap.step = item.id;
    // 🔴 Отрезок берётся ИЗ ЗАПИСИ: у краевых случаев он бывает
    // отрицательным или дробным, и подстановка нуля стёрла бы проверку.
    const from = item.from ?? 0;
    const to = item.to ?? 1;
    try {
      const code = `$: ${item.expr}`;
      window.strudelMirror.setCode(code);
      await window.strudelMirror.repl.evaluate(code, false);
      // 🔴 Булка НЕ БРОСАЕТ на негодном коде: она оставляет прежний паттерн
      // и кладёт причину в state.evalError. Без этой проверки эталон
      // молча наполняется событиями ПРЕДЫДУЩЕГО выражения.
      const st = window.strudelMirror.repl.state;
      if (st.evalError) throw new Error(String(st.evalError));
      const haps = st.pattern.queryArc(from, to);
      window.__cap.out[item.id] = {
        n: haps.length,
        from,
        to,
        haps: haps.map((h) => [
          h.whole ? fr(h.whole.begin) : '',
          h.whole ? fr(h.whole.end) : '',
          fr(h.part.begin),
          fr(h.part.end),
          h.value,
        ]),
      };
    } catch (e) {
      window.__cap.out[item.id] = { error: String(e) };
      window.__cap.errors.push(item.id);
    }
  }
  await fetch('http://127.0.0.1:4199/haps', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    // 🔴 Значения бывают со СЧЁТНЫМИ ЦЕЛЫМИ (BigInt) — дроби Strudel
    // хранятся именно так, и JSON.stringify на них падает.
    body: JSON.stringify(window.__cap.out, (k, v) => (typeof v === 'bigint' ? Number(v) : v)),
  });
  window.strudelMirror.setCode(window.__savedCode);
  await window.strudelMirror.repl.evaluate(window.__savedCode, false);
  window.__cap.done = true;
})();
