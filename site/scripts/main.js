// Link destinations and the version live in the HTML, so the page works without
// scripts. This keeps the copyright year current (the HTML carries a fallback) and
// fades sections in as they scroll into view.
document.querySelectorAll("[data-site-year]").forEach((element) => {
  element.textContent = new Date().getFullYear();
});

// The hidden starting state exists only under html.js with motion allowed (see
// styles/main.css), so without JavaScript or with Reduce Motion every section is
// simply visible.
const reveals = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window && reveals.length) {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
  reveals.forEach((element) => observer.observe(element));
} else {
  reveals.forEach((element) => element.classList.add("is-visible"));
}
