(() => {
  const more = document.querySelector("footer .more");
  const rest = document.getElementById("more-guides");
  if (more && rest) {
    more.addEventListener("click", () => {
      const open = more.getAttribute("aria-expanded") === "true";
      more.setAttribute("aria-expanded", String(!open));
      rest.hidden = open;
      more.textContent = open ? "More" : "Less";
    });
  }
  const extra = document.getElementById("blog-more");
  if (extra) {
    extra.addEventListener("click", () => {
      document.querySelectorAll("[data-more]").forEach((item) => { item.hidden = false; });
      const row = extra.closest(".read-more");
      if (row) row.hidden = true;
      else extra.hidden = true;
    });
  }
  document.querySelectorAll("[data-share-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      const wrap = button.closest("[data-share]");
      const done = wrap.querySelector("[data-share-done]");
      try {
        await navigator.clipboard.writeText(wrap.dataset.url);
        done.textContent = "Link copied";
      } catch (err) {
        done.textContent = "Copy the address from the bar";
      }
    });
  });
  const links = [...document.querySelectorAll(".toc a")];
  if (links.length && "IntersectionObserver" in window) {
    const byId = new Map(links.map((a) => [a.getAttribute("href").slice(1), a]));
    const mark = (id) => links.forEach((a) => a.classList.toggle("is-here", a === byId.get(id)));
    const observer = new IntersectionObserver((entries) => {
      const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (visible) mark(visible.target.id);
    }, { rootMargin: "-20% 0px -60% 0px", threshold: [0, 1] });
    byId.forEach((_, id) => {
      const node = document.getElementById(id);
      if (node) observer.observe(node);
    });
  }
})();
