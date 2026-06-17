import re
from typing import List, Dict, TypedDict

class MarkdownLink(TypedDict):
    title: str
    url: str

def extract_markdown_links(markdown: str) -> List[MarkdownLink]:
    """
    Extract all links from a Markdown string.
    - Inline: [text](url "opt title")
    - Autolink: <url>
    - Reference: [text][id] with a matching `[id]: url` definition
    Images (starting with "!") are ignored.
    """
    results: List[MarkdownLink] = []

    # --- 1) Collect reference definitions: [id]: URL "optional title"
    ref_def_re = re.compile(r'^\s{0,3}\[([^\]\r\n]+)\]:\s*<?([^\s>]+)>?(?:\s+["\'(].*?["\')])?\s*$', re.MULTILINE | re.IGNORECASE)
    references: Dict[str, str] = {}  # id (lowercased) -> URL

    for match in ref_def_re.finditer(markdown):
        ref_id = match.group(1).strip().lower()
        url = match.group(2).strip()
        references[ref_id] = url

    # Helper to push a link result
    def push(title: str, url: str):
        if not url:
            return
        results.append({"title": title or "", "url": url})

    # --- 2) Inline links: [text](url [title])
    inline_link_re = re.compile(r'(?<!!)\[(?P<text>[^\]]*)\]\((?P<inside>[^)]+)\)|!\[(?P<img>[^\]]*)\]\([^)]+\)')

    for match in inline_link_re.finditer(markdown):
        # Skip image matches
        if match.group('img') is not None:
            continue

        text = (match.group('text') or "").strip()
        inside = (match.group('inside') or "").strip()

        # Extract URL as the first token
        url = ""
        if inside.startswith("<"):
            gt = inside.find(">")
            if gt > 0:
                url = inside[1:gt].strip()
            else:
                url = inside.replace("<", "").replace(">", "").strip()
        else:
            # Split on whitespace; first token is URL
            tokens = inside.split()
            url = tokens[0].strip() if tokens else ""

        push(text or "", url)

    # --- 3) Autolinks: <scheme:...>
    autolink_re = re.compile(r'<([a-zA-Z][a-zA-Z0-9+.-]*:[^>\s]+)>')
    for match in autolink_re.finditer(markdown):
        url = match.group(1).strip()
        push("", url)  # no explicit title -> empty string

    # --- 4) Reference-style links: [text][id] or [text][]
    ref_link_re = re.compile(r'(?<!!)\[(?P<text>[^\]]+)\]\[(?P<id>[^\]\r\n]*)\]|!\[(?P<img2>[^\]]+)\]\[[^\]\r\n]*\]')

    for match in ref_link_re.finditer(markdown):
        # Skip image matches
        if match.group('img2') is not None:
            continue

        text = (match.group('text') or "").strip()
        raw_id = (match.group('id') or "").strip()
        ref_id = (raw_id or text).lower()  # shortcut reference: [text][]
        url = references.get(ref_id, "")

        push(text or "", url)

    return results


def replace_markdown_links_with_order(markdown: str) -> str:
    """
    Replace all Markdown links by their order of appearance: [1], [2], ...
    - Inline: [text](url)            -> [1]
    - Reference: [text][id] / [text][] -> [2]
    - Autolink: <https://...> or <user@example.com> -> [3]
    - Skips images: ![alt](...) and ![alt][id]
    - Skips code blocks (```/~~~) and inline code (`...`)
    - Leaves link definition lines `[id]: url` untouched
    """
    # Helper functions
    def intersects(a: Dict[str, int], b: Dict[str, int]) -> bool:
        return not (a['end'] <= b['start'] or b['end'] <= a['start'])

    def is_inside_excluded(start: int, end: int, excluded: List[Dict[str, int]]) -> bool:
        return any(intersects({'start': start, 'end': end}, r) for r in excluded)

    # Collect excluded ranges: fenced code blocks, inline code, and link definition lines
    excluded: List[Dict[str, int]] = []

    # Fenced code blocks ```...``` and ~~~...~~~
    fenced_re = re.compile(r'(```|~~~)[^\n]*\n[\s\S]*?\n\1')
    for match in fenced_re.finditer(markdown):
        excluded.append({'start': match.start(), 'end': match.end()})

    # Inline code: `...` (not across newlines)
    inline_code_re = re.compile(r'`[^`\n]*`')
    for match in inline_code_re.finditer(markdown):
        start, end = match.start(), match.end()
        if not is_inside_excluded(start, end, excluded):
            excluded.append({'start': start, 'end': end})

    # Link definition lines: [id]: url "opt"
    def_line_re = re.compile(r'^\s{0,3}\[[^\]\r\n]+\]:[^\n]*$', re.MULTILINE)
    for match in def_line_re.finditer(markdown):
        excluded.append({'start': match.start(), 'end': match.end()})

    # ---------- collect all link occurrences ----------
    hits: List[Dict[str, int]] = []

    # 1) Inline links: [text](url "title") — match images too & skip those
    inline_link_re = re.compile(r'!?\[[^\]]*\]\([^)]+\)')
    for match in inline_link_re.finditer(markdown):
        start, end = match.start(), match.end()
        if match.group(0).startswith('!'):
            continue  # skip images
        if not is_inside_excluded(start, end, excluded):
            hits.append({'start': start, 'end': end})

    # 2) Reference-style: [text][id] and [text][]
    ref_link_re = re.compile(r'!?\[[^\]]+\]\[[^\]\r\n]*\]')
    for match in ref_link_re.finditer(markdown):
        start, end = match.start(), match.end()
        if match.group(0).startswith('!'):
            continue  # skip image reference
        if not is_inside_excluded(start, end, excluded):
            hits.append({'start': start, 'end': end})

    # 3) Autolinks: <scheme:...> or <email@host>
    autolink_re = re.compile(r'<([^>\s]+)>')
    for match in autolink_re.finditer(markdown):
        start, end = match.start(), match.end()
        inner = match.group(1)

        looks_like_url = re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:[^\s]+$', inner)
        looks_like_email = re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', inner)

        if (looks_like_url or looks_like_email) and not is_inside_excluded(start, end, excluded):
            hits.append({'start': start, 'end': end})

    # Sort by appearance
    hits.sort(key=lambda h: h['start'])

    # ---------- build the replaced text ----------
    result = ''
    cursor = 0
    for i, hit in enumerate(hits):
        result += markdown[cursor:hit['start']] + f"[{i + 1}]"
        cursor = hit['end']
    result += markdown[cursor:]
    return result
 


