#!/usr/bin/env ruby
# Generates assets/cv/cv_data.yml from _data/cv.yml + papers.bib,
# then compiles assets/cv/template.typ → assets/pdf/BurnhamEmilieCV.pdf via typst.

require "yaml"
require "pathname"
require "open3"
require "fileutils"
require "bibtex"
require "date"

ROOT          = Pathname.new(File.expand_path("..", __dir__))
CV_PATH       = ROOT.join("_data/cv.yml")
CONFIG_PATH   = ROOT.join("_config.yml")
TEMPLATE_PATH = ROOT.join("assets/cv/template.typ")
DATA_OUT      = ROOT.join("assets/cv/cv_data.yml")
PDF_OUT       = ROOT.join("assets/pdf/BurnhamEmilieCV.pdf")
CV_PDF_META   = ROOT.join("_data/cv_pdf.yml")

def load_yaml(path)
  YAML.safe_load(path.read, aliases: true) || {}
end

def present?(v)
  !v.nil? && !v.to_s.strip.empty?
end

# Extract a 4-digit year from any value ("Spring 2026", 2023, "2024-06", etc.)
def extract_year(value)
  return nil unless present?(value)
  m = value.to_s.match(/\b(\d{4})\b/)
  m ? m[1].to_i : nil
end

def build_education(entries)
  Array(entries).map do |e|
    h = {
      "institution" => e["institution"],
      "degree"      => e["studyType"] || e["degree"],
      "area"        => e["area"],
      "start_year"  => extract_year(e["start_date"]),
      "end_year"    => extract_year(e["end_date"]),
      "location"    => e["location"],
      "highlights"  => Array(e["highlights"]).map(&:to_s).reject(&:empty?),
    }
    h.delete("highlights") if h["highlights"].empty?
    h.compact
  end
end

def build_experience(entries)
  Array(entries).map do |e|
    company  = e["company"]  || e["name"] || e["organization"] || e["institution"]
    position = e["position"] || e["role"] || e["title"]
    {
      "company"    => company,
      "position"   => position,
      "start_year" => extract_year(e["start_date"]),
      "end_year"   => extract_year(e["end_date"]),
      "location"   => e["location"],
      "summary"    => present?(e["summary"]) ? e["summary"] : nil,
    }.compact
  end
end

def build_teaching(entries)
  Array(entries).map do |e|
    {
      "institution" => e["institution"],
      "course"      => e["course"],
      "role"        => e["role"],
      "start_year"  => extract_year(e["start_date"]),
      "location"    => e["location"],
    }.compact
  end
end

def build_awards(entries)
  Array(entries).map do |e|
    {
      "name"    => e["title"],
      "year"    => extract_year(e["date"]),
      "awarder" => e["awarder"],
    }.compact
  end
end

def build_leadership(entries)
  Array(entries).map do |e|
    {
      "title"        => e["title"],
      "organization" => e["organization"],
      "start_year"   => extract_year(e["start_date"]),
      "end_year"     => extract_year(e["end_date"]),
      "location"     => e["location"],
      "summary"      => present?(e["summary"]) ? e["summary"] : nil,
    }.compact
  end
end

def build_outreach(entries)
  Array(entries).map do |e|
    {
      "title"        => e["title"],
      "organization" => e["organization"],
      "year"         => extract_year(e["date"]),
      "location"     => e["location"],
    }.compact
  end
end

def build_venue(v)
  out = {
    "venue"    => v["venue"],
    "location" => v["location"],
    "year"     => extract_year(v["date"]),
  }
  out["award"]    = v["award"]    if present?(v["award"])
  out["emphasis"] = v["emphasis"] if present?(v["emphasis"])
  out.compact
end

def build_talks(entries)
  Array(entries).map do |e|
    {
      "title"  => e["title"],
      "venues" => Array(e["venues"]).map { |v| build_venue(v) },
    }
  end
end

def build_presentations(section)
  return {} unless section.is_a?(Hash)
  # Accept either "Invited Talks" or "invited_talks" key variants
  find = ->(h, *keys) { keys.map { |k| h[k] }.compact.first || [] }
  {
    "invited_talks"      => build_talks(find.(section, "Invited Talks",      "invited_talks")),
    "contributed_talks"  => build_talks(find.(section, "Contributed Talks",  "contributed_talks")),
    "contributed_posters"=> build_talks(find.(section, "Contributed Posters","contributed_posters")),
  }
end

def pub_venue(entry)
  %i[journal booktitle series publisher].each do |f|
    v = entry[f].to_s
    return v unless v.empty?
  end
  ""
end

def first_author?(entry, first_names, last_names)
  return false if first_names.empty? || last_names.empty?
  return false unless entry[:author]
  first = entry[:author].to_a.map(&:to_s).first.to_s.downcase.gsub(/[^\p{Alnum}\s]/, " ").strip
  last_names.any? { |ln| first.include?(ln.downcase) } &&
    first_names.any? { |fn|
      first.include?(fn.downcase) || first.include?((fn[0] || "").downcase)
    }
end

# ── Load data ─────────────────────────────────────────────────────────────────

abort("Missing #{CV_PATH}") unless CV_PATH.exist?
cv_root  = load_yaml(CV_PATH)
config   = load_yaml(CONFIG_PATH)
cv       = cv_root["cv"] || {}
sections = cv["sections"] || {}

scholar     = config["scholar"] || {}
source_dir  = (scholar["source"] || "_bibliography/").sub(%r{^/}, "")
bib_path    = ROOT.join(source_dir, scholar["bibliography"] || "papers.bib")
abort("Bibliography not found: #{bib_path}") unless bib_path.exist?

bib = BibTeX::Bibliography.parse(bib_path.read, symbolize: true)
bib.replace_strings
entries = bib.select { |e| e.is_a?(BibTeX::Entry) }

first_names = Array(scholar["first_name"] || []).map(&:to_s)
last_names  = Array(scholar["last_name"]  || []).map(&:to_s)

first_pubs = []
co_pubs    = []
entries.each do |entry|
  pub = {
    "title"   => entry[:title].to_s,
    "authors" => entry[:author] ? entry[:author].to_a.map(&:to_s) : [],
    "journal" => pub_venue(entry),
    "year"    => extract_year(entry[:year].to_s),
    "url"     => entry[:ads_url].to_s.empty? ? entry[:url].to_s : entry[:ads_url].to_s,
  }.compact
  pub.delete("url")     if pub["url"].to_s.empty?
  pub.delete("journal") if pub["journal"].to_s.empty?
  if first_author?(entry, first_names, last_names)
    first_pubs << pub
  else
    co_pubs << pub
  end
end

# Prefer explicit cv.yml publication lists over bib auto-detection
if sections["First-Author Publications"].is_a?(Array) && !sections["First-Author Publications"].empty?
  first_pubs = sections["First-Author Publications"].map do |e|
    {
      "title"   => e["title"],
      "authors" => Array(e["authors"]).map(&:to_s),
      "journal" => e["publisher"] || e["journal"],
      "year"    => extract_year(e["releaseDate"] || e["date"] || e["year"]),
      "url"     => e["url"],
    }.compact
  end
end

if sections["Co-Author Publications"].is_a?(Array) && !sections["Co-Author Publications"].empty?
  co_pubs = sections["Co-Author Publications"].map do |e|
    {
      "title"   => e["title"],
      "authors" => Array(e["authors"]).map(&:to_s),
      "journal" => e["publisher"] || e["journal"],
      "year"    => extract_year(e["releaseDate"] || e["date"] || e["year"]),
      "url"     => e["url"],
    }.compact
  end
end

github_net = Array(cv["social_networks"]).find { |n| n["network"] == "GitHub" }

skills = Array(sections["Skills"]).map do |s|
  kw = s["keywords"]
  kw = Array(kw).join(", ") if kw.is_a?(Array)
  { "label" => s["name"], "keywords" => kw.to_s }.compact
end

cv_data = {
  "name"                      => cv["name"],
  "label"                     => cv["label"],
  "email"                     => cv["email"],
  "location"                  => cv["location"],
  "github"                    => github_net&.dig("username"),
  "summary"                   => cv["summary"],
  "education"                 => build_education(sections["Education"]),
  "research_experience"       => build_experience(sections["Research Experience"]),
  "industry_experience"       => build_experience(sections["Industry Experience"]),
  "teaching_experience"       => build_teaching(sections["Teaching Experience"]),
  "first_author_publications" => first_pubs,
  "co_author_publications"    => co_pubs,
  "awards"                    => build_awards(sections["Awards"]),
  "leadership_service"        => build_leadership(sections["Leadership / Service"]),
  "outreach"                  => build_outreach(sections["Outreach"]),
  "presentations"             => build_presentations(sections["Professional Presentations"]),
  "skills"                    => skills,
}.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }

FileUtils.mkdir_p(DATA_OUT.dirname)
DATA_OUT.write(cv_data.to_yaml)
puts "Wrote #{DATA_OUT}"

# ── Find Python with typst package ───────────────────────────────────────────

TYPST_COMPILE_PY = ROOT.join("bin/typst_compile.py")

def find_python(root)
  candidates = [
    ENV["PYTHON_BIN"],
    root.join(".venv/bin/python3.14").to_s,
    root.join(".venv/bin/python3.13").to_s,
    root.join(".venv/bin/python3.12").to_s,
    root.join(".venv/bin/python3.11").to_s,
    root.join(".venv/bin/python3").to_s,
    root.join(".venv/bin/python").to_s,
    `sh -lc 'command -v python3' 2>/dev/null`.strip,
    `sh -lc 'command -v python'  2>/dev/null`.strip,
  ].compact.reject(&:empty?)

  candidates.each do |py|
    next unless File.executable?(py.to_s)
    result = `#{Shellwords.escape(py)} -c "import typst; print('ok')" 2>/dev/null`.strip
    return py if result == "ok"
  end
  nil
end

require "shellwords"
python_bin = find_python(ROOT)
abort("No Python with typst package found. Run: pip install -r requirements.txt") unless python_bin

# ── Compile ───────────────────────────────────────────────────────────────────

FileUtils.mkdir_p(PDF_OUT.dirname)
cmd = [python_bin, TYPST_COMPILE_PY.to_s, TEMPLATE_PATH.to_s, PDF_OUT.to_s]
stdout, stderr, status = Open3.capture3(*cmd, chdir: ROOT.to_s)
puts stdout unless stdout.empty?
warn stderr unless stderr.empty?
abort("typst compile failed (exit #{status.exitstatus})") unless status.success?
puts "Generated #{PDF_OUT}"

# ── Update cv_pdf metadata ────────────────────────────────────────────────────

CV_PDF_META.write({
  "path"         => "/assets/pdf/BurnhamEmilieCV.pdf",
  "filename"     => "BurnhamEmilieCV.pdf",
  "last_updated" => Date.today.strftime("%Y-%m-%d"),
}.to_yaml)
puts "Updated #{CV_PDF_META}"
