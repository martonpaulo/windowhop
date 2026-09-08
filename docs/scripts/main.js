const WINDOWHOP_SITE = Object.freeze({
  version: "1.6.1",
  website: "https://martonpaulo.com/windowhop/",
  github: "https://github.com/martonpaulo/windowhop",
  issues: "https://github.com/martonpaulo/windowhop/issues",
  releases: "https://github.com/martonpaulo/windowhop/releases",
  releaseNotes: "https://github.com/martonpaulo/windowhop/releases/tag/v1.6.1",
  download: "https://github.com/martonpaulo/windowhop/releases/latest/download/WindowHop-1.6.1-Installer.zip",
  license: "https://github.com/martonpaulo/windowhop/blob/main/LICENSE",
  altTab: "https://github.com/lwouis/alt-tab-macos",
});

document.querySelectorAll("[data-link]").forEach((link) => {
  const destination = WINDOWHOP_SITE[link.dataset.link];
  if (destination) link.href = destination;
});

document.querySelectorAll("[data-site-version]").forEach((element) => {
  element.textContent = WINDOWHOP_SITE.version;
});

document.querySelectorAll("[data-site-year]").forEach((element) => {
  element.textContent = new Date().getFullYear();
});
