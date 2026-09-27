document.querySelectorAll('[data-scroll]').forEach((item) => {
  item.addEventListener('click', (event) => {
    const target = document.querySelector(item.getAttribute('href'));
    if (target) {
      event.preventDefault();
      target.scrollIntoView({behavior: 'smooth'});
    }
  });
});
