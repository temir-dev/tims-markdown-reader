(() => {
  "use strict";

  const diagramElements = Array.from(
    document.querySelectorAll("[data-mermaid-diagram]")
  );
  if (diagramElements.length === 0) return;

  const sources = diagramElements.map((element) => element.textContent || "");
  const colorScheme = window.matchMedia("(prefers-color-scheme: dark)");
  // Consistent slices in both appearances, with dark text on light fills.
  const pieColors = ["#8fb9ed", "#ba9fdf", "#86c9b2", "#e7b580",
    "#dc9eb4", "#9dcbd8", "#c5ca85", "#9cabe0",
    "#daa78f", "#b3bdc9", "#98c38b", "#d6b6d5"];
  let generation = 0;
  let rendering = Promise.resolve();

  function showError(element) {
    const message = document.createElement("span");
    message.className = "mermaid-error-message";
    message.textContent = "Unable to render this Mermaid diagram.";
    element.classList.remove("is-rendering");
    element.classList.add("mermaid-error");
    element.setAttribute("role", "alert");
    element.replaceChildren(message);
  }

  function sandboxedFrame(markup, title, appearance) {
    const template = document.createElement("template");
    template.innerHTML = markup.trim();
    const frame = template.content.firstElementChild;

    if (!(frame instanceof HTMLIFrameElement) ||
        template.content.childElementCount !== 1) {
      throw new Error("Mermaid sandbox did not return one iframe.");
    }

    const source = frame.getAttribute("src") || "";
    const prefix = "data:text/html;charset=UTF-8;base64,";
    if (!source.startsWith(prefix)) {
      throw new Error("Mermaid sandbox returned an unexpected frame URL.");
    }

    const binary = window.atob(source.slice(prefix.length));
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    const frameDocument = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    // The sandbox is a separate document: the reader's background and color
    // scheme do not carry into it. Pair its canvas with the diagram's palette.
    const content = new DOMParser().parseFromString(frameDocument, "text/html");
    content.documentElement.style.colorScheme = appearance.scheme;
    content.documentElement.style.backgroundColor = appearance.background;
    content.body.style.backgroundColor = appearance.background;

    frame.removeAttribute("src");
    frame.setAttribute("sandbox", "");
    frame.setAttribute("referrerpolicy", "no-referrer");
    frame.setAttribute("title", title);
    frame.srcdoc = "<!doctype html>" + content.documentElement.outerHTML;
    return frame;
  }

  async function renderAll(requestGeneration) {
    if (typeof globalThis.mermaid !== "object") {
      diagramElements.forEach(showError);
      return;
    }

    const readingStyle = getComputedStyle(document.documentElement);
    const fontFamily = readingStyle.fontFamily;
    const fontSize = parseFloat(readingStyle.fontSize) || 17;
    const appearance = {
      scheme: colorScheme.matches ? "dark" : "light",
      background: readingStyle.getPropertyValue("--subtle").trim()
    };
    globalThis.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "sandbox",
      // Diagram frontmatter/directives must not alter the sanitizer policy.
      // Retain Mermaid's default protected keys when extending this list.
      secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize",
        "suppressErrorRendering", "maxEdges", "dompurifyConfig"],
      suppressErrorRendering: true,
      maxTextSize: 500 * 1024,
      deterministicIds: true,
      deterministicIDSeed: "markdown-reader",
      logLevel: "fatal",
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      fontFamily,
      fontSize,
      themeVariables: {
        fontFamily,
        fontSize: `${fontSize}px`,
        ...Object.fromEntries(pieColors.map((color, index) => [`pie${index + 1}`, color])),
        pieSectionTextColor: "#202124",
        pieTitleTextColor: readingStyle.getPropertyValue("--foreground").trim(),
        pieLegendTextColor: readingStyle.getPropertyValue("--foreground").trim(),
        pieStrokeColor: appearance.background,
        pieOuterStrokeColor: readingStyle.getPropertyValue("--border").trim(),
        pieOpacity: 1
      },
      theme: appearance.scheme === "dark" ? "dark" : "default"
    });

    for (let index = 0; index < diagramElements.length; index += 1) {
      if (requestGeneration !== generation) return;

      const element = diagramElements[index];
      element.classList.remove("mermaid-error");
      element.classList.add("is-rendering");
      element.setAttribute("role", "img");
      element.setAttribute("aria-label", `Mermaid diagram ${index + 1}`);

      try {
        const result = await globalThis.mermaid.render(
          `markdown-reader-mermaid-${requestGeneration}-${index}`,
          sources[index]
        );
        if (requestGeneration !== generation) return;

        const frame = sandboxedFrame(result.svg, `Mermaid diagram ${index + 1}`, appearance);
        element.classList.remove("is-rendering");
        element.replaceChildren(frame);
      } catch {
        if (requestGeneration === generation) showError(element);
      }
    }
  }

  function scheduleRender() {
    generation += 1;
    const requestGeneration = generation;
    rendering = rendering
      .then(() => renderAll(requestGeneration))
      .catch(() => diagramElements.forEach(showError));
  }

  let settingsTimer;
  window.addEventListener("reader-settings-changed", () => {
    clearTimeout(settingsTimer);
    settingsTimer = setTimeout(scheduleRender, 150);
  });
  colorScheme.addEventListener("change", scheduleRender);
  scheduleRender();
})();
