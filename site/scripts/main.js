// Link destinations and the version live in the HTML, so the page works without
// scripts. This only keeps the copyright year current; the HTML carries a fallback.
document.querySelectorAll("[data-site-year]").forEach((element) => {
  element.textContent = new Date().getFullYear();
});
