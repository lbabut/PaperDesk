const form = document.querySelector('#interest-form');
const note = document.querySelector('#form-note');

form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  const submit = form.querySelector('button[type="submit"]');
  submit.disabled = true;
  note.textContent = 'Saving your place…';
  const values = new FormData(form);
  try {
    const response = await fetch('/api/interest', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        email: values.get('email'),
        useCase: values.get('useCase'),
        consent: values.get('consent') === 'yes'
      })
    });
    if (!response.ok) throw new Error('request failed');
    form.reset();
    note.textContent = 'You’re on the founding list. We’ll only write about PaperDesk.';
  } catch (_) {
    note.textContent = 'Could not save this yet. Please try again in a moment.';
  } finally {
    submit.disabled = false;
  }
});

document.querySelectorAll('[data-scroll]').forEach((item) => {
  item.addEventListener('click', (event) => {
    const target = document.querySelector(item.getAttribute('href'));
    if (target) {
      event.preventDefault();
      target.scrollIntoView({behavior: 'smooth'});
    }
  });
});

