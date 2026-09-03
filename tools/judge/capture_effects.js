// Снятие ЗВУКОВОГО эталона с живой Булки: каждый узел цепи по отдельности.
//
// Порядок тот же, что у capture_tunes.js: поднять приёмник, открыть Булку,
// КЛИКНУТЬ по странице (без жеста звук не поднимается), вставить это в
// консоль.
//
// Скачивание перехватывается: `renderPatternAudio` кладёт готовый WAV в
// blob и жмёт на ссылку — мы подменяем `URL.createObjectURL` и клик, чтобы
// звук ушёл приёмнику, а не в папку загрузок.
window.__fx = { done: false, step: 'старт', errors: [] };
(async () => {
  const list = await (await fetch('http://127.0.0.1:4199/effects')).json();
  const origCreate = URL.createObjectURL;
  const origClick = HTMLAnchorElement.prototype.click;
  for (const item of list) {
    window.__fx.step = item.id;
    let blob = null;
    URL.createObjectURL = (b) => { blob = b; return 'blob:capture'; };
    HTMLAnchorElement.prototype.click = function () {};
    try {
      const code = `$: ${item.expr}`;
      window.strudelMirror.setCode(code);
      await window.strudelMirror.repl.evaluate(code, false);
      const pat = window.strudelMirror.repl.state.pattern;
      // Четыре секунды при половине круга в секунду — два круга, 48 кГц.
      await window.renderPatternAudio(pat, 0.5, 0, 2, 48000, 128, false, item.id);
      if (!blob) throw new Error('звук не собрался');
      const buf = await blob.arrayBuffer();
      await fetch('http://127.0.0.1:4199/fx_' + item.id, {
        method: 'POST',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: buf,
      });
    } catch (e) {
      window.__fx.errors.push(item.id + ': ' + String(e));
    } finally {
      URL.createObjectURL = origCreate;
      HTMLAnchorElement.prototype.click = origClick;
    }
  }
  window.strudelMirror.setCode(window.__savedCode);
  await window.strudelMirror.repl.evaluate(window.__savedCode, false);
  window.__fx.done = true;
})();
