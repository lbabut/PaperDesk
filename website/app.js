document.querySelectorAll('[data-scroll]').forEach((item) => {
  item.addEventListener('click', (event) => {
    const target = document.querySelector(item.getAttribute('href'));
    if (target) {
      event.preventDefault();
      target.scrollIntoView({behavior: 'auto'});
    }
  });
});

const downloadCount = document.querySelector('[data-download-count]');
if (downloadCount) {
  fetch('/api/download-count', {cache: 'no-store'})
    .then((response) => {
      if (!response.ok) throw new Error('Download count unavailable');
      return response.json();
    })
    .then(({downloaded}) => {
      if (Number.isInteger(downloaded) && downloaded >= 0) {
        downloadCount.textContent = `Downloaded: ${downloaded}`;
      }
    })
    .catch(() => {
      downloadCount.textContent = 'Downloaded: —';
    });
}

const mapDialog = document.querySelector('#download-map');
if (downloadCount && mapDialog) {
  const status = mapDialog.querySelector('[data-map-status]');
  const svg = mapDialog.querySelector('[data-world-map]');
  const list = mapDialog.querySelector('[data-country-list]');
  const ns = 'http://www.w3.org/2000/svg';
  const names = new Intl.DisplayNames(['en'], {type: 'region'});
  let loading = false;
  mapDialog.querySelector('[data-close-map]').addEventListener('click', () => mapDialog.close());
  downloadCount.addEventListener('click', async () => {
    mapDialog.showModal();
    if (loading) return;
    loading = true;
    status.textContent = 'Loading map…';
    try {
      const responses = await Promise.all([
        fetch('/api/download-countries', {cache: 'no-store'}),
        fetch('/assets/countries.geojson')
      ]);
      if (responses.some(response => !response.ok)) throw new Error('Unavailable');
      const [stats, world] = await Promise.all(responses.map(response => response.json()));
      const countries = stats.countries;
      const maximum = Math.max(1, ...Object.values(countries).filter(Number.isInteger));
      svg.replaceChildren();
      for (const feature of world.features) {
        const code = feature.properties.ISO_A2_EH || feature.properties.ISO_A2;
        const count = countries[code] || 0;
        const path = document.createElementNS(ns, 'path');
        const polygons = feature.geometry.type === 'Polygon' ? [feature.geometry.coordinates] : feature.geometry.coordinates;
        path.setAttribute('d', polygons.map(polygon => polygon.map(ring => ring.map(([lon, lat], i) => `${i ? 'L' : 'M'}${((lon + 180) * 1000 / 360).toFixed(2)},${((90 - lat) * 500 / 180).toFixed(2)}`).join(' ') + 'Z').join(' ')).join(' '));
        path.setAttribute('fill', count ? `hsl(159 45% ${75 - 45 * Math.log1p(count) / Math.log1p(maximum)}%)` : '#e4e2da');
        path.setAttribute('fill-rule', 'evenodd');
        const title = document.createElementNS(ns, 'title');
        title.textContent = `${feature.properties.NAME_EN || feature.properties.NAME}: ${count} downloads`;
        path.append(title);
        svg.append(path);
      }
      list.replaceChildren();
      for (const [code, count] of Object.entries(countries).sort((a, b) => b[1] - a[1])) {
        if (!count) continue;
        const item = document.createElement('li');
        item.textContent = `${code === 'ZZ' ? 'Unknown / earlier downloads' : names.of(code)}: ${count}`;
        list.append(item);
      }
      status.textContent = `${stats.downloaded} downloads in total · Darker green means more downloads. Grey means no recorded downloads.`;
      downloadCount.textContent = `Downloaded: ${stats.downloaded}`;
    } catch (error) {
      status.textContent = 'The download map is unavailable. Close it and try again.';
      svg.replaceChildren();
      list.replaceChildren();
    } finally {
      loading = false;
    }
  });
}
