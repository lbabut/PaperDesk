(() => {
  const tabs = [...document.querySelectorAll('[data-tab]')];
  const panels = [...document.querySelectorAll('[data-panel]')];
  const aliases = {calc:'apps', top:'home', main:'home', tools:'apps', tour:'apps', download:'install', compatibility:'install', release:'install', makers:'about', support:'about'};
  function selectView() {
    const fragment = location.hash.slice(1) || 'home';
    const view = aliases[fragment] || fragment;
    const selected = panels.some(panel => panel.dataset.panel === view) ? view : 'home';
    panels.forEach(panel => { panel.hidden = panel.dataset.panel !== selected; });
    tabs.forEach(tab => {
      const active = tab.dataset.tab === selected;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
    });
    if(fragment === 'calc') {
      document.querySelectorAll('[data-app]').forEach(item => item.setAttribute('aria-pressed', String(item.dataset.app === 'calc')));
      document.querySelectorAll('[data-app-stage]').forEach(stage => {
        stage.hidden = stage.dataset.appStage !== 'calc';
        if(!stage.hidden) stage.querySelector('img').loading = 'eager';
      });
    }
    const label = tabs.find(tab => tab.dataset.tab === selected)?.textContent || 'Home';
    document.title = selected === 'home' ? 'PaperDesk 4 — make room for curiosity' : label + ' · PaperDesk';
  }
  addEventListener('hashchange', () => { selectView(); window.scrollTo({top:0,behavior:'instant'}); });
  tabs.forEach((tab,index) => {
    tab.addEventListener('keydown', event => {
      let next;
      if(event.key === 'ArrowRight') next = (index + 1) % tabs.length;
      if(event.key === 'ArrowLeft') next = (index - 1 + tabs.length) % tabs.length;
      if(event.key === 'Home') next = 0;
      if(event.key === 'End') next = tabs.length - 1;
      if(next === undefined) return;
      event.preventDefault();
      location.hash = tabs[next].dataset.tab;
      tabs[next].focus();
    });
  });
  document.querySelectorAll('[data-app]').forEach(button => {
    button.addEventListener('click', () => {
      const selected = button.dataset.app;
      document.querySelectorAll('[data-app]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
      document.querySelectorAll('[data-app-stage]').forEach(stage => {
        stage.hidden = stage.dataset.appStage !== selected;
        if(!stage.hidden) stage.querySelector('img').loading = 'eager';
      });
    });
  });
  selectView();
})();
