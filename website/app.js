document.querySelectorAll('[data-scroll]').forEach((item) => {
  item.addEventListener('click', (event) => {
    const target = document.querySelector(item.getAttribute('href'));
    if (target) {
      event.preventDefault();
      target.scrollIntoView({behavior: 'smooth'});
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
