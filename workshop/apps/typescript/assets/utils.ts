export type MarkdownLink = { title: string; url: string };

export class Utils {
    /**
     * Extract all links from a Markdown string.
     * - Inline: [text](url "opt title")
     * - Autolink: <url>
     * - Reference: [text][id] with a matching `[id]: url` definition
     * Images (starting with "!") are ignored.
     */
    static extractMarkdownLinks(markdown: string): MarkdownLink[] {
        const results: MarkdownLink[] = [];

        // --- 1) Collect reference definitions: [id]: URL "optional title"
        // Matches lines like:
        //   [id]: https://example.com "Title"
        //   [ID]: <https://example.com>
        const refDefRe = /^\s{0,3}\[([^\]\r\n]+)\]:\s*<?([^\s>]+)>?(?:\s+["'(].*?["')])?\s*$/gim;
        const references = new Map<string, string>(); // id (lowercased) -> URL

        let defMatch: RegExpExecArray | null;
        while ((defMatch = refDefRe.exec(markdown)) !== null) {
            const id = defMatch[1].trim().toLowerCase();
            const url = defMatch[2].trim();
            references.set(id, url);
        }

        // Helper to push a link result
        const push = (title: string, url: string) => {
            if (!url) return;
            results.push({ title: title ?? "", url });
        };

        // --- 2) Inline links: [text](url [title])
        // Ignore images via negative lookbehind for "!" (fallback check if env lacks lookbehind)
        // We capture the whole (...) then parse the URL as the first token, allowing an optional title after it.
        const inlineLinkRe =
            /(?<!!)\[(?<text>[^\]]*)\]\((?<inside>[^)]+)\)|!\[(?<img>[^\]]*)\]\([^)]+\)/g;

        let ilMatch: RegExpExecArray | null;
        while ((ilMatch = inlineLinkRe.exec(markdown)) !== null) {
            // If it's actually an image match (because some JS engines may not support lookbehind), skip it:
            if (ilMatch.groups && ilMatch.groups.img !== undefined) continue;

            const text = (ilMatch.groups?.text ?? "").trim();

            const inside = (ilMatch.groups?.inside ?? "").trim();
            // Extract URL as the first token (respect optional angle brackets and optional title after)
            let url = "";
            if (inside.startsWith("<")) {
            const gt = inside.indexOf(">");
            if (gt > 0) url = inside.slice(1, gt).trim();
            else url = inside.replace(/[<>]/g, "").trim();
            } else {
            // Split on whitespace; first token is URL
            url = inside.split(/\s+/)[0]?.trim() ?? "";
            }

            push(text || "", url);
        }

        // --- 3) Autolinks: <scheme:...>
        const autolinkRe = /<([a-zA-Z][a-zA-Z0-9+.-]*:[^>\s]+)>/g;
        let alMatch: RegExpExecArray | null;
        while ((alMatch = autolinkRe.exec(markdown)) !== null) {
            const url = alMatch[1].trim();
            push("", url); // no explicit title -> empty string
        }

        // --- 4) Reference-style links:
        // [text][id]  or  [text][] (uses the text as the id)
        // (Again, skip images.)
        const refLinkRe =
            /(?<!!)\[(?<text>[^\]]+)\]\[(?<id>[^\]\r\n]*)\]|!\[(?<img2>[^\]]+)\]\[[^\]\r\n]*\]/g;

        let rlMatch: RegExpExecArray | null;
        while ((rlMatch = refLinkRe.exec(markdown)) !== null) {
            if (rlMatch.groups && rlMatch.groups.img2 !== undefined) continue;

            const text = (rlMatch.groups?.text ?? "").trim();
            const rawId = (rlMatch.groups?.id ?? "").trim();
            const id = (rawId || text).toLowerCase(); // shortcut reference: [text][]
            const url = references.get(id) ?? "";

            push(text || "", url);
        }

        return results;
    }

    /**
     * Replace all Markdown links by their order of appearance: [1], [2], ...
     * - Inline: [text](url)            -> [1]
     * - Reference: [text][id] / [text][] -> [2]
     * - Autolink: <https://...> or <user@example.com> -> [3]
     * - Skips images: ![alt](...) and ![alt][id]
     * - Skips code blocks (```/~~~) and inline code (`...`)
     * - Leaves link definition lines `[id]: url` untouched
     */
    static replaceMarkdownLinksWithOrder(markdown: string): string {
        type Range = { start: number; end: number };
        type Hit = { start: number; end: number };

        // ---------- helpers ----------
        const intersects = (a: Range, b: Range) => !(a.end <= b.start || b.end <= a.start);
        const isInsideExcluded = (start: number, end: number, excluded: Range[]) =>
            excluded.some(r => intersects({ start, end }, r));

        // Collect excluded ranges: fenced code blocks, inline code, and link definition lines
        const excluded: Range[] = [];

        // Fenced code blocks ```...``` and ~~~...~~~
        const fencedRE = /(```|~~~)[^\n]*\n[\s\S]*?\n\1/g;
        for (const m of markdown.matchAll(fencedRE)) {
            excluded.push({ start: m.index!, end: m.index! + m[0].length });
        }

        // Inline code: `...` (not across newlines). Avoid portions inside fenced blocks.
        const inlineCodeRE = /`[^`\n]*`/g;
        for (const m of markdown.matchAll(inlineCodeRE)) {
            const start = m.index!, end = start + m[0].length;
            if (!isInsideExcluded(start, end, excluded)) excluded.push({ start, end });
        }

        // Link definition lines:   [id]: url "opt"
        const defLineRE = /^\s{0,3}\[[^\]\r\n]+\]:[^\n]*$/gm;
        for (const m of markdown.matchAll(defLineRE)) {
            excluded.push({ start: m.index!, end: m.index! + m[0].length });
        }

        // ---------- collect all link occurrences ----------
        const hits: Hit[] = [];

        // 1) Inline links: [text](url "title") — match images too & skip those
        const inlineLinkRE = /!?\[[^\]]*\]\([^)]+\)/g;
        for (const m of markdown.matchAll(inlineLinkRE)) {
            const start = m.index!, end = start + m[0].length;
            if (m[0].startsWith('!')) continue; // skip images
            if (!isInsideExcluded(start, end, excluded)) hits.push({ start, end });
        }

        // 2) Reference-style: [text][id] and [text][]
        const refLinkRE = /!?\[[^\]]+\]\[[^\]\r\n]*\]/g;
        for (const m of markdown.matchAll(refLinkRE)) {
            const start = m.index!, end = start + m[0].length;
            if (m[0].startsWith('!')) continue; // skip image reference
            if (!isInsideExcluded(start, end, excluded)) hits.push({ start, end });
        }

        // 3) Autolinks: <scheme:...> or <email@host>
        const autolinkRE = /<([^>\s]+)>/g;
        for (const m of markdown.matchAll(autolinkRE)) {
            const start = m.index!, end = start + m[0].length;
            const inner = m[1];

            const looksLikeUrl = /^[a-zA-Z][a-zA-Z0-9+.-]*:[^\s]+$/.test(inner);
            const looksLikeEmail = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(inner);

            if ((looksLikeUrl || looksLikeEmail) && !isInsideExcluded(start, end, excluded)) {
            hits.push({ start, end });
            }
        }

        // Sort by appearance
        hits.sort((a, b) => a.start - b.start);

        // ---------- build the replaced text ----------
        let result = '';
        let cursor = 0;
        hits.forEach((hit, i) => {
            result += markdown.slice(cursor, hit.start) + `[${i + 1}]`;
            cursor = hit.end;
        });
        result += markdown.slice(cursor);
        return result;
    }

} 


