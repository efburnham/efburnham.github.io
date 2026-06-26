#!/usr/bin/env python3
"""
Reads _data/cv.yml + _bibliography/papers.bib, writes assets/cv/cv_data.yml,
then compiles assets/cv/template.typ → assets/pdf/BurnhamEmilieCV.pdf.
"""

import pathlib
import re
import sys
import datetime
import yaml
import bibtexparser

ROOT = pathlib.Path(__file__).resolve().parent.parent
CV_YML      = ROOT / "_data" / "cv.yml"
BIB_PATH    = ROOT / "_bibliography" / "papers.bib"
DATA_OUT    = ROOT / "assets" / "cv" / "cv_data.yml"
TEMPLATE    = ROOT / "assets" / "cv" / "template.typ"
PDF_OUT     = ROOT / "assets" / "pdf" / "BurnhamEmilieCV.pdf"
CV_PDF_META = ROOT / "_data" / "cv_pdf.yml"


def extract_year(value):
    if not value:
        return None
    m = re.search(r"\b(\d{4})\b", str(value))
    return int(m.group(1)) if m else None


def yr_range(start, end):
    a = extract_year(start)
    b = extract_year(end)
    if not a:
        return ""
    if not b:
        return f"{a}–"
    return str(a) if a == b else f"{a}–{b}"


def build_education(entries):
    result = []
    for e in entries or []:
        h = {
            "institution": e.get("institution"),
            "degree":      e.get("studyType") or e.get("degree"),
            "area":        e.get("area"),
            "start_year":  extract_year(e.get("start_date")),
            "end_year":    extract_year(e.get("end_date")),
            "location":    e.get("location"),
            "highlights":  [str(x) for x in (e.get("highlights") or []) if x],
        }
        if not h["highlights"]:
            del h["highlights"]
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_experience(entries):
    result = []
    for e in entries or []:
        company  = e.get("company") or e.get("name") or e.get("organization") or e.get("institution")
        position = e.get("position") or e.get("role") or e.get("title")
        h = {
            "company":    company,
            "position":   position,
            "start_year": extract_year(e.get("start_date")),
            "end_year":   extract_year(e.get("end_date")),
            "location":   e.get("location"),
            "summary":    e.get("summary") or None,
        }
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_teaching(entries):
    result = []
    for e in entries or []:
        h = {
            "institution": e.get("institution"),
            "course":      e.get("course"),
            "role":        e.get("role"),
            "start_year":  extract_year(e.get("start_date")),
            "location":    e.get("location"),
        }
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_awards(entries):
    result = []
    for e in entries or []:
        h = {
            "name":    e.get("title"),
            "year":    extract_year(e.get("date")),
            "awarder": e.get("awarder"),
            "summary": e.get("summary") or None,
        }
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_leadership(entries):
    result = []
    for e in entries or []:
        h = {
            "title":        e.get("title"),
            "organization": e.get("organization"),
            "start_year":   extract_year(e.get("start_date")),
            "end_year":     extract_year(e.get("end_date")),
            "location":     e.get("location"),
            "summary":      e.get("summary") or None,
        }
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_outreach(entries):
    result = []
    for e in entries or []:
        h = {
            "title":        e.get("title"),
            "organization": e.get("organization"),
            "year":         extract_year(e.get("date")),
            "location":     e.get("location"),
            "summary":      e.get("summary") or None,
        }
        result.append({k: v for k, v in h.items() if v is not None})
    return result


def build_venue(v):
    h = {
        "venue":    v.get("venue"),
        "location": v.get("location"),
        "year":     extract_year(v.get("date")),
        "award":    v.get("award") or None,
        "emphasis": v.get("emphasis") or None,
    }
    return {k: val for k, val in h.items() if val is not None}


def build_talks(entries):
    result = []
    for e in entries or []:
        result.append({
            "title":  e.get("title"),
            "venues": [build_venue(v) for v in (e.get("venues") or [])],
        })
    return result


def build_presentations(section):
    if not isinstance(section, dict):
        return {}
    def find(keys):
        for k in keys:
            if k in section:
                return section[k]
        return []
    return {
        "invited_talks":       build_talks(find(["Invited Talks",       "invited_talks"])),
        "contributed_talks":   build_talks(find(["Contributed Talks",   "contributed_talks"])),
        "contributed_posters": build_talks(find(["Contributed Posters", "contributed_posters"])),
    }


def build_skills(entries):
    result = []
    for s in entries or []:
        kw = s.get("keywords")
        if isinstance(kw, list):
            kw = ", ".join(str(x) for x in kw)
        result.append({"label": s.get("name"), "keywords": str(kw or "")})
    return result


def load_bib_pubs(bib_path, cv_name_parts):
    """
    Classify bib entries as first-author or co-author based on whether
    any of the cv_name_parts (last names) appear as the FIRST listed author.
    """
    with open(bib_path) as fh:
        library = bibtexparser.load(fh)
    first_pubs, co_pubs = [], []
    for entry in library.entries:
        fields = entry  # bibtexparser v1: entry IS the dict
        title   = fields.get("title", "").replace("{", "").replace("}", "")
        authors_raw = fields.get("author", "")
        # split on " and "
        authors = [a.strip() for a in re.split(r"\s+and\s+", authors_raw) if a.strip()]
        year    = extract_year(fields.get("year"))
        journal = (fields.get("journal") or fields.get("booktitle") or
                   fields.get("series") or fields.get("publisher") or "")
        journal = journal.replace("{", "").replace("}", "")
        url     = fields.get("ads_url") or fields.get("url") or ""

        pub = {k: v for k, v in {
            "title":   title,
            "authors": authors,
            "journal": journal or None,
            "year":    year,
            "url":     url or None,
        }.items() if v is not None}

        # Check if first author matches any name part
        first_author = authors[0].lower() if authors else ""
        is_first = any(part.lower() in first_author for part in cv_name_parts if part)

        if is_first:
            first_pubs.append(pub)
        else:
            co_pubs.append(pub)

    return first_pubs, co_pubs


# ── Load cv.yml ────────────────────────────────────────────────────────────────

with open(CV_YML) as f:
    cv_root = yaml.safe_load(f)

cv       = cv_root.get("cv", {})
sections = cv.get("sections", {})

# ── Name parts for first-author detection ─────────────────────────────────────

full_name  = cv.get("name", "")
name_parts = [p.strip() for p in full_name.replace(",", " ").split() if p.strip()]

# ── Publications: prefer explicit cv.yml lists; fall back to bib ──────────────

cv_first = sections.get("First-Author Publications") or []
cv_co    = sections.get("Co-Author Publications") or []

def parse_cv_pub(e):
    return {k: v for k, v in {
        "title":   e.get("title"),
        "authors": e.get("authors") or [],
        "journal": e.get("publisher") or e.get("journal") or None,
        "year":    extract_year(e.get("releaseDate") or e.get("date") or e.get("year")),
        "url":     e.get("url") or None,
    }.items() if v is not None}

bib_first, bib_co = load_bib_pubs(BIB_PATH, name_parts)

# Use explicit cv.yml list when non-empty; otherwise fall back to bib.
first_pubs = [parse_cv_pub(e) for e in cv_first] if cv_first else bib_first
co_pubs    = [parse_cv_pub(e) for e in cv_co]    if cv_co    else bib_co

# Sort both lists by year descending (most recent first); entries without a year go last.
first_pubs.sort(key=lambda p: p.get("year") or 0, reverse=True)
co_pubs.sort(   key=lambda p: p.get("year") or 0, reverse=True)

# ── GitHub handle ──────────────────────────────────────────────────────────────

github_net = next(
    (n for n in (cv.get("social_networks") or []) if n.get("network") == "GitHub"),
    None,
)

# ── Assemble output ────────────────────────────────────────────────────────────

today = datetime.date.today().strftime("%B %d, %Y")

cv_data = {k: v for k, v in {
    "name":                      cv.get("name"),
    "last_updated":              today,
    "label":                     cv.get("label"),
    "email":                     cv.get("email"),
    "location":                  cv.get("location"),
    "github":                    github_net["username"] if github_net else None,
    "summary":                   cv.get("summary") or None,
    "education":                 build_education(sections.get("Education")),
    "research_experience":       build_experience(sections.get("Research Experience")),
    "industry_experience":       build_experience(sections.get("Industry Experience")),
    "teaching_experience":       build_teaching(sections.get("Teaching Experience")),
    "first_author_publications": first_pubs,
    "co_author_publications":    co_pubs,
    "awards":                    build_awards(sections.get("Awards")),
    "leadership_service":        build_leadership(sections.get("Leadership / Service")),
    "outreach":                  build_outreach(sections.get("Outreach")),
    "presentations":             build_presentations(sections.get("Professional Presentations")),
    "skills":                    build_skills(sections.get("Skills")),
}.items() if v not in (None, [], {})}

DATA_OUT.parent.mkdir(parents=True, exist_ok=True)
with open(DATA_OUT, "w") as f:
    yaml.dump(cv_data, f, allow_unicode=True, sort_keys=False)
print(f"Wrote {DATA_OUT}")

# ── Compile PDF ────────────────────────────────────────────────────────────────

import typst

PDF_OUT.parent.mkdir(parents=True, exist_ok=True)
pdf_bytes = typst.compile(str(TEMPLATE))
PDF_OUT.write_bytes(pdf_bytes)
print(f"Compiled {TEMPLATE} → {PDF_OUT}")

# ── Update metadata ────────────────────────────────────────────────────────────

meta = {
    "path":         "/assets/pdf/BurnhamEmilieCV.pdf",
    "filename":     "BurnhamEmilieCV.pdf",
    "last_updated": datetime.date.today().isoformat(),
}
with open(CV_PDF_META, "w") as f:
    yaml.dump(meta, f)
print(f"Updated {CV_PDF_META}")
