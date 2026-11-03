// 共用介面：狀態列、拖曳上傳、畫面顯示切換
const $ = id => document.getElementById(id);
const UI = {
  status(text, kind = '') { const b = $('statusbar'); b.className = 'statusbar ' + kind; $('status').textContent = text; },
  showMedia() { $('stage').classList.add('has-media'); },
  hideMedia() { $('stage').classList.remove('has-media'); },
};
(function () {
  const stage = $('stage'), input = $('imageInput');
  ['dragenter', 'dragover'].forEach(t => stage.addEventListener(t, e => { e.preventDefault(); stage.classList.add('drag'); }));
  ['dragleave', 'drop'].forEach(t => stage.addEventListener(t, e => { e.preventDefault(); stage.classList.remove('drag'); }));
  stage.addEventListener('drop', e => {
    const f = e.dataTransfer.files[0];
    if (!f || !f.type.startsWith('image/')) return;
    const dt = new DataTransfer(); dt.items.add(f); input.files = dt.files;
    input.dispatchEvent(new Event('change'));
  });
})();
