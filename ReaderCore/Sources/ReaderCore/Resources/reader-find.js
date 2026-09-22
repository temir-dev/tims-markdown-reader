(() => {
  "use strict";

  // Injected into the app's isolated script world: document scripts cannot see
  // or call it. Matches are painted with the CSS Custom Highlight API, so the
  // document's DOM is never modified.
  const supported = typeof Highlight === "function" &&
    typeof CSS === "object" && CSS.highlights !== undefined;
  const allName = "reader-find";
  const currentName = "reader-find-current";
  const maximumMatches = 10000;
  // A noncharacter keeps matches from spanning separate blocks. Unlike a
  // newline, flexible whitespace in the query cannot match it.
  const blockSeparator = "￿";
  const blockSelector = "p,li,td,th,h1,h2,h3,h4,h5,h6,pre,blockquote,figcaption,dt,dd,div,section";
  const skippedSelector = "script,style,template,iframe,.mermaid-diagram";
  let ranges = [];
  let current = -1;
  // Start of the match the reader was on before the query changed.
  let previousCurrent = null;
  let limited = false;

  function state() {
    return { supported, count: ranges.length, index: current, limited };
  }

  function clear() {
    ranges = [];
    current = -1;
    previousCurrent = null;
    limited = false;
    if (supported) {
      CSS.highlights.delete(allName);
      CSS.highlights.delete(currentName);
    }
    return state();
  }

  function collectText() {
    const root = document.querySelector("main.reader") || document.body;
    const segments = [];
    let text = "";
    if (!root) return { text, segments };

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const parent = node.parentElement;
        return parent && !parent.closest(skippedSelector)
          ? NodeFilter.FILTER_ACCEPT
          : NodeFilter.FILTER_REJECT;
      }
    });
    let previousBlock = null;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.data.length === 0) continue;
      const block = node.parentElement.closest(blockSelector) || root;
      if (previousBlock !== null && block !== previousBlock) text += blockSeparator;
      previousBlock = block;
      segments.push({ node, start: text.length });
      text += node.data;
    }
    return { text, segments };
  }

  function pattern(query) {
    const escaped = query
      .replace(/[\r\n]+/g, " ")
      .replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&")
      // Soft line breaks render as spaces but remain newlines in text nodes.
      .replace(/\s+/g, "\\s+");
    return new RegExp(escaped, "giu");
  }

  function segmentIndex(segments, offset) {
    let low = 0;
    let high = segments.length - 1;
    while (low < high) {
      const middle = (low + high + 1) >> 1;
      if (segments[middle].start <= offset) low = middle;
      else high = middle - 1;
    }
    return low;
  }

  function firstMatchFromViewport() {
    // Ranges are in document order, which is close enough to vertical order
    // for a binary search to the first match at or below the viewport's top.
    let low = 0;
    let high = ranges.length - 1;
    let answer = 0;
    while (low <= high) {
      const middle = (low + high) >> 1;
      if (ranges[middle].getBoundingClientRect().bottom >= 0) {
        answer = middle;
        high = middle - 1;
      } else {
        low = middle + 1;
      }
    }
    return ranges[answer].getBoundingClientRect().bottom >= 0 ? answer : 0;
  }

  function paint() {
    if (!supported) return;
    if (ranges.length === 0) {
      CSS.highlights.delete(allName);
      CSS.highlights.delete(currentName);
      return;
    }
    CSS.highlights.set(allName, new Highlight(...ranges));
    const currentHighlight = new Highlight(ranges[current]);
    currentHighlight.priority = 1;
    CSS.highlights.set(currentName, currentHighlight);
  }

  function reveal() {
    const range = ranges[current];
    if (!range) return;

    // Bring the match into view inside wide tables and code blocks first.
    for (let element = range.startContainer.parentElement;
      element && element !== document.body;
      element = element.parentElement) {
      if (element.scrollWidth <= element.clientWidth) continue;
      const box = element.getBoundingClientRect();
      const rect = range.getBoundingClientRect();
      if (rect.left < box.left || rect.right > box.right) {
        element.scrollLeft += rect.left - box.left - (box.width - rect.width) / 2;
      }
    }

    // Leave the page where it is when the match is already comfortably visible.
    const rect = range.getBoundingClientRect();
    const margin = Math.min(80, window.innerHeight / 4);
    if (rect.top >= margin && rect.bottom <= window.innerHeight - margin) return;
    const target = window.scrollY + rect.top - (window.innerHeight - rect.height) / 2;
    window.scrollTo({ top: Math.max(0, target), behavior: "instant" });
  }

  function keepCurrentIfStillMatching() {
    if (!previousCurrent) return -1;
    return ranges.findIndex((range) =>
      range.startContainer === previousCurrent.startContainer &&
      range.startOffset === previousCurrent.startOffset);
  }

  function search(query, shouldReveal) {
    // Refining a query should keep the reader on the same match when it still
    // matches, instead of hopping to whichever match is nearest the viewport top.
    const remembered = current >= 0 && ranges[current]
      ? { startContainer: ranges[current].startContainer, startOffset: ranges[current].startOffset }
      : null;
    clear();
    previousCurrent = remembered;
    if (!supported || typeof query !== "string" || query.trim().length === 0) return state();

    let expression;
    try {
      expression = pattern(query);
    } catch {
      return state();
    }

    const { text, segments } = collectText();
    if (segments.length === 0) return state();

    for (let match = expression.exec(text); match; match = expression.exec(text)) {
      if (match[0].length === 0) {
        expression.lastIndex += 1;
        continue;
      }
      if (ranges.length >= maximumMatches) {
        limited = true;
        break;
      }
      const first = segments[segmentIndex(segments, match.index)];
      const last = segments[segmentIndex(segments, match.index + match[0].length - 1)];
      const range = document.createRange();
      range.setStart(first.node, match.index - first.start);
      range.setEnd(last.node, match.index + match[0].length - last.start);
      ranges.push(range);
    }

    if (ranges.length === 0) return state();
    const kept = keepCurrentIfStillMatching();
    current = kept >= 0 ? kept : firstMatchFromViewport();
    previousCurrent = null;
    paint();
    if (shouldReveal !== false) reveal();
    return state();
  }

  function step(delta) {
    if (ranges.length === 0) return state();
    const count = ranges.length;
    current = (((current + (delta < 0 ? -1 : 1)) % count) + count) % count;
    paint();
    reveal();
    return state();
  }

  window.readerFind = { search, step, clear };
})();
