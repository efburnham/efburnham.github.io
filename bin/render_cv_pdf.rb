#!/usr/bin/env ruby

require "yaml"
require "tempfile"
require "pathname"
require "open3"
require "fileutils"
require "bibtex"
require "date"

ROOT = Pathname.new(File.expand_path("..", __dir__))
CONFIG_PATH = ROOT.join("_config.yml")
CV_PATH = ROOT.join("_data/cv.yml")
SETTINGS_PATH = ROOT.join("assets/rendercv/settings.yaml")
DESIGN_PATH = ROOT.join("assets/rendercv/design.yaml")
LOCALE_PATH = ROOT.join("assets/rendercv/locale.yaml")
OUTPUT_DIR = ROOT.join("assets/rendercv/rendercv_output")
STABLE_PDF_PATH = ROOT.join("assets/pdf/cv.pdf")
PDF_DATA_PATH = ROOT.join("_data/cv_pdf.yml")

def load_yaml(path)
  YAML.safe_load(path.read, aliases: true) || {}
end

def truthy_bibtex_value?(value)
  value.to_s.strip.downcase == "true"
end

def present?(value)
  !value.nil? && !value.to_s.strip.empty?
end

def publication_venue(entry)
  %i[journal booktitle series publisher].each do |field|
    value = entry[field].to_s
    return value if present?(value)
  end
  ""
end

def compact_hash(hash)
  hash.each_with_object({}) do |(key, value), memo|
    next if value.nil?
    next if value.respond_to?(:empty?) && value.empty?

    memo[key] = value
  end
end

def parse_date_string(value)
  return nil unless present?(value)

  string = value.to_s.strip
  return string if string.match?(/^\d{4}(-\d{2})?(-\d{2})?$/)
  return string if string.downcase == "present"

  season_map = {
    "spring" => "03",
    "summer" => "06",
    "fall" => "09",
    "autumn" => "09",
    "winter" => "12",
  }

  if (match = string.match(/\A(Spring|Summer|Fall|Autumn|Winter)\s+(\d{4})\z/i))
    month = season_map[match[1].downcase]
    return "#{match[2]}-#{month}"
  end

  if (match = string.match(/\A\d{4}\z/))
    return match[0]
  end

  string
end

def format_date_range(entry)
  start_date = parse_date_string(entry["start_date"])
  end_date = parse_date_string(entry["end_date"])
  date = parse_date_string(entry["date"] || entry["releaseDate"])

  result = {}
  if start_date && (start_date.match?(/^\d{4}(-\d{2})?(-\d{2})?$/) || start_date == "present")
    result["start_date"] = start_date
  elsif start_date
    result["date"] = start_date
  end

  if end_date && result["start_date"]
    result["end_date"] = end_date
  elsif end_date && !result["date"]
    result["date"] = end_date
  end

  result["date"] ||= date if date
  result
end

def normalize_highlights(value)
  Array(value).map(&:to_s).map(&:strip).reject(&:empty?)
end

def normalize_str(value)
  value.to_s.strip
end

def blank_str?(value)
  normalize_str(value).empty?
end

def humanize_date(date_value)
  date = normalize_str(date_value)
  return "" if date.empty?

  if date.match?(/^\d{4}$/)
    date
  elsif (match = date.match(/^(\d{4})-(\d{2})$/))
    month_names = {
      "01" => "Jan", "02" => "Feb", "03" => "Mar", "04" => "Apr",
      "05" => "May", "06" => "Jun", "07" => "Jul", "08" => "Aug",
      "09" => "Sep", "10" => "Oct", "11" => "Nov", "12" => "Dec",
    }
    "#{month_names[match[2]]} #{match[1]}"
  else
    date
  end
end

def experience_title_and_affiliation(entry)
  role = normalize_str(entry["position"] || entry["role"] || entry["title"] || entry["job_title"] || entry["course"])
  affiliation = normalize_str(entry["company"] || entry["institution"] || entry["organization"] || entry["affiliation"])
  [role, affiliation]
end

def normalize_experience_entries(entries)
  Array(entries).map do |entry|
    next entry unless entry.is_a?(Hash)

    out = entry.dup
    role, affiliation = experience_title_and_affiliation(entry)

    # In RenderCV classic, company is emphasized and position is normal weight.
    out["company"] = role unless role.empty?
    out["name"] = role unless role.empty?
    out["position"] = affiliation unless affiliation.empty?
    out
  end
end

def normalize_award_entries(entries)
  Array(entries).map do |entry|
    next entry unless entry.is_a?(Hash)

    out = entry.dup
    awarder = normalize_str(out["awarder"])
    venue = normalize_str(out["venue"])
    author0 = normalize_str(Array(out["authors"]).first)

    out["venue"] = nil if !awarder.empty? && !venue.empty? && awarder.casecmp?(venue)
    if !awarder.empty? && !author0.empty? && awarder.casecmp?(author0)
      out["authors"] = Array(out["authors"])[1..] || []
    end
    out
  end
end

def presentation_group_order
  ["Invited Talks", "Contributed Talks", "Contributed Posters"]
end

def normalize_presentations_section(section)
  return section unless section.is_a?(Hash)

  grouped = {}
  presentation_group_order.each { |group| grouped[group] = [] }

  section.each do |group_name, entries|
    canonical = presentation_group_order.find { |g| g.downcase == group_name.to_s.downcase }
    canonical ||= if group_name.to_s.downcase.include?("invited")
                    "Invited Talks"
                  elsif group_name.to_s.downcase.include?("poster")
                    "Contributed Posters"
                  else
                    "Contributed Talks"
                  end
    grouped[canonical].concat(Array(entries))
  end

  grouped.transform_values do |entries|
    Array(entries).map do |entry|
      next entry unless entry.is_a?(Hash)

      out = entry.dup
      venues = Array(out["venues"]).map do |venue|
        next venue unless venue.is_a?(Hash)
        venue_bits = []
        venue_bits << normalize_str(venue["venue"])
        venue_bits << normalize_str(venue["location"])
        date = humanize_date(venue["date"])
        venue_bits << date unless date.empty?
        venue_bits << normalize_str(venue["award"])
        venue_bits << normalize_str(venue["emphasis"])
        venue.merge("_display" => venue_bits.reject(&:empty?).join(" | "))
      end
      out["venues"] = venues
      out
    end
  end
end

def normalize_cv_for_pdf!(cv_data)
  sections = cv_data["sections"] || {}
  %w[Research\ Experience Industry\ Experience Teaching\ Experience Leadership\ /\ Service Outreach].each do |key|
    sections[key] = normalize_experience_entries(sections[key]) if sections[key]
  end

  sections["Awards"] = normalize_award_entries(sections["Awards"]) if sections["Awards"]

  if sections["Professional Presentations"].is_a?(Hash)
    sections["Professional Presentations"] = normalize_presentations_section(sections["Professional Presentations"])
  end

  cv_data["sections"] = sections
  cv_data
end

def build_summary(entry, extra_parts = [])
  parts = Array(extra_parts).map(&:to_s).map(&:strip).reject(&:empty?)
  parts << entry["summary"].to_s.strip if present?(entry["summary"])
  parts.join(". ")
end

def education_entries(entries)
  Array(entries).map do |entry|
    compact_hash({
      "institution" => entry["institution"],
      "location" => entry["location"],
      "area" => entry["area"],
      "degree" => entry["studyType"] || entry["degree"],
      **format_date_range(entry),
      "highlights" => normalize_highlights(entry["highlights"]),
      "summary" => build_summary(entry),
    })
  end
end

def experience_entries(entries)
  Array(entries).map do |entry|
    company = entry["name"] || entry["company"] || entry["organization"] || entry["institution"]
    position = entry["position"] || entry["role"] || entry["title"] || entry["course"]
    extra_parts = []
    extra_parts << entry["course"] if present?(entry["course"]) && entry["course"] != position

    compact_hash({
      "company" => company,
      "position" => position,
      "location" => entry["location"],
      **format_date_range(entry),
      "summary" => build_summary(entry, extra_parts),
      "highlights" => normalize_highlights(entry["highlights"]),
    })
  end
end

def publication_entries(entries)
  Array(entries).map do |entry|
    date = parse_date_string(entry["releaseDate"] || entry["date"] || entry["year"])

    compact_hash({
      "title" => entry["title"],
      "authors" => Array(entry["authors"]).map(&:to_s),
      "journal" => entry["publisher"] || entry["journal"] || entry["venue"],
      "url" => entry["url"],
      "date" => date,
    })
  end
end

def award_entries(entries)
  Array(entries).map do |entry|
    issuer_bits = [entry["awarder"], entry["venue"], *Array(entry["authors"]).map(&:to_s)].map { |value| value.to_s.strip }.reject(&:empty?)
    summary_bits = []
    summary_bits << issuer_bits.join(". ") unless issuer_bits.empty?
    summary_bits << entry["summary"].to_s.strip if present?(entry["summary"])

    compact_hash({
      "name" => entry["title"],
      "date" => parse_date_string(entry["date"]),
      "summary" => summary_bits.join(". "),
    })
  end
end

def one_line_entries(entries)
  Array(entries).map do |entry|
    details = entry["details"] || entry["keywords"]
    details = Array(details).join(", ") if details.is_a?(Array)

    compact_hash({
      "label" => entry["label"] || entry["name"],
      "details" => details,
    })
  end
end

def bullet_entries(entries)
  Array(entries).filter_map do |entry|
    if entry.is_a?(String)
      { "bullet" => entry }
    else
      bits = []
      bits << entry["title"] if present?(entry["title"])
      bits << entry["organization"] if present?(entry["organization"])
      bits << entry["awarder"] if present?(entry["awarder"])
      bits << entry["location"] if present?(entry["location"])
      bits << entry["date"] if present?(entry["date"])
      bits << entry["summary"] if present?(entry["summary"])
      bullet = bits.join(". ")
      next nil unless present?(bullet)

      { "bullet" => bullet }
    end
  end
end

def presentation_bullets(section_hash)
  presentation_group_order.flat_map do |subsection_title|
    entries = section_hash[subsection_title] || []
    next [] if entries.empty?

    group_lines = ["**#{subsection_title}**"]
    Array(entries).each do |entry|
      next unless entry.is_a?(Hash)
      title = normalize_str(entry["title"])
      group_lines << "- \"#{title}\"" unless title.empty?

      Array(entry["venues"]).each do |venue|
        next unless venue.is_a?(Hash)
        location_line = normalize_str(venue["_display"])
        location_line = [venue["venue"], venue["location"], humanize_date(venue["date"]), venue["award"], venue["emphasis"]].map { |v| normalize_str(v) }.reject(&:empty?).join(" | ") if location_line.empty?
        group_lines << "  - #{location_line}" unless location_line.empty?
      end

      summary = normalize_str(entry["summary"])
      group_lines << "  - #{summary}" unless summary.empty?
    end

    [{ "bullet" => group_lines.join("\n") }]
  end
end

def build_rendercv_sections(cv_data)
  sections = cv_data["sections"] || {}
  rendercv_sections = {}

  summary_entries = []
  summary_entries << cv_data["summary"].to_s if present?(cv_data["summary"])
  rendercv_sections["Research Interests"] = summary_entries if summary_entries.any?

  rendercv_sections["Education"] = education_entries(sections["Education"]) if sections["Education"]
  rendercv_sections["Research Experience"] = experience_entries(sections["Research Experience"]) if sections["Research Experience"]
  rendercv_sections["Industry Experience"] = experience_entries(sections["Industry Experience"]) if sections["Industry Experience"]
  rendercv_sections["Teaching Experience"] = experience_entries(sections["Teaching Experience"]) if sections["Teaching Experience"]
  rendercv_sections["First-Author Publications"] = publication_entries(sections["First-Author Publications"]) if sections["First-Author Publications"]
  rendercv_sections["Co-Author Publications"] = publication_entries(sections["Co-Author Publications"]) if sections["Co-Author Publications"]
  rendercv_sections["Awards"] = award_entries(sections["Awards"]) if sections["Awards"]
  rendercv_sections["Leadership / Service"] = experience_entries(sections["Leadership / Service"]) if sections["Leadership / Service"]
  rendercv_sections["Outreach"] = experience_entries(sections["Outreach"]) if sections["Outreach"]
  rendercv_sections["Professional Presentations"] = presentation_bullets(sections["Professional Presentations"]) if sections["Professional Presentations"]
  rendercv_sections["Skills"] = one_line_entries(sections["Skills"]) if sections["Skills"]

  rendercv_sections
end

def build_rendercv_input(cv_root, config)
  cv_data = cv_root["cv"] || {}
  today = Date.today
  dated_pdf_name = "BurnhamEmilieCV_#{today.strftime('%Y-%m-%d')}.pdf"

  actual_location = cv_data["location"]
  if !present?(actual_location) && cv_data["address"].is_a?(Hash)
    address = cv_data["address"]
    actual_location = [address["city"], address["region"], address["countryCode"]].compact.join(", ")
  end

  contact_bits = []
  contact_bits << cv_data["email"] if present?(cv_data["email"])
  github_network = Array(cv_data["social_networks"]).find { |network| network["network"] == "GitHub" && present?(network["username"]) }
  contact_bits << "GitHub: #{github_network['username']}" if github_network
  contact_bits << actual_location if present?(actual_location)

  location_lines = []
  if present?(cv_data["label"]) && contact_bits.any?
    location_lines << "#{cv_data['label'].to_s.strip} | #{contact_bits.join(' | ')}"
  elsif present?(cv_data["label"])
    location_lines << cv_data["label"].to_s.strip
  elsif contact_bits.any?
    location_lines << contact_bits.join(" | ")
  end
  location = location_lines.reject(&:empty?).join("\n")

  cv = compact_hash({
    "name" => cv_data["name"],
    "location" => location,
    "sections" => build_rendercv_sections(cv_root["cv"] || {}),
  })

  compact_hash({
    "cv" => cv,
  }).merge({ "_dated_pdf_name" => dated_pdf_name })
end

def month_value(value)
  month = value.to_s.strip.downcase
  return month.to_i if month.match?(/^\d+$/)

  month_names = {
    "jan" => 1,
    "feb" => 2,
    "mar" => 3,
    "apr" => 4,
    "may" => 5,
    "jun" => 6,
    "jul" => 7,
    "aug" => 8,
    "sep" => 9,
    "oct" => 10,
    "nov" => 11,
    "dec" => 12,
  }

  month_names.each do |key, number|
    return number if month.start_with?(key)
  end

  0
end

def normalize_value(value)
  value.to_s.strip.downcase
end

def compare_key(a, b, key)
  case key
  when "year"
    b[:year].to_i <=> a[:year].to_i
  when "month"
    month_value(b[:month]) <=> month_value(a[:month])
  when "author"
    normalize_value(a[:author].to_s) <=> normalize_value(b[:author].to_s)
  else
    normalize_value(b[key.to_sym].to_s) <=> normalize_value(a[key.to_sym].to_s)
  end
end

def sort_entries(entries, sort_keys)
  entries.sort do |a, b|
    sort_keys.map { |key| compare_key(a, b, key) }.find { |result| result != 0 } || 0
  end
end

def normalize_name(value)
  value.to_s.gsub(/[^\p{Alnum}\s]/, " ").strip.downcase
end

def first_author?(entry, first_names, last_names)
  return false if first_names.empty? || last_names.empty?
  return false unless entry[:author]

  authors = entry[:author].to_a.map(&:to_s).compact
  return false if authors.empty?

  first_author = normalize_name(authors.first)
  normalized_first = first_names.flat_map { |name| [name.to_s.strip.downcase, name.to_s.strip[0]&.downcase] }.compact
  normalized_last = last_names.map { |name| name.to_s.strip.downcase }

  normalized_last.any? do |last|
    first_author.include?(last) && normalized_first.any? { |first| first_author.include?(first) }
  end
end

def bib_entry_to_cv_publication(entry)
  authors = entry[:author] ? entry[:author].to_a.map(&:to_s) : []

  publication = {
    "title" => entry[:title].to_s,
    "authors" => authors,
    "publisher" => publication_venue(entry),
    "releaseDate" => entry[:year].to_s,
    "url" => entry[:ads_url].to_s.empty? ? entry[:url].to_s : entry[:ads_url].to_s,
  }

  abstract = entry[:abstract].to_s
  publication["summary"] = abstract if present?(abstract)
  publication
end

def detect_rendercv_bin
  return ENV["RENDERCV_BIN"] if ENV["RENDERCV_BIN"] && File.executable?(ENV["RENDERCV_BIN"])

  found = `sh -lc 'command -v rendercv'`.strip
  return found unless found.empty?

  local_bin = ROOT.join(".venv/bin/rendercv")
  return local_bin.to_s if local_bin.exist?

  nil
end

def resolve_pdf_output_path(settings_path)
  explicit_pdf = Dir.glob(OUTPUT_DIR.join("*.pdf").to_s).sort.last
  return Pathname.new(explicit_pdf) if explicit_pdf

  settings = load_yaml(settings_path)
  relative_pdf = settings.dig("settings", "render_command", "pdf_path")
  return nil unless relative_pdf

  ROOT.join("_data").join(relative_pdf).expand_path(ROOT)
end

abort("Missing #{CONFIG_PATH}") unless CONFIG_PATH.exist?
abort("Missing #{CV_PATH}") unless CV_PATH.exist?
abort("Missing #{SETTINGS_PATH}") unless SETTINGS_PATH.exist?
abort("Missing #{DESIGN_PATH}") unless DESIGN_PATH.exist?
abort("Missing #{LOCALE_PATH}") unless LOCALE_PATH.exist?

config = load_yaml(CONFIG_PATH)
cv_root = load_yaml(CV_PATH)

cv_data = cv_root["cv"] || {}
sections = cv_data["sections"] || {}

scholar = config["scholar"] || {}
bibliography = scholar["bibliography"] || "papers.bib"
source_dir = (scholar["source"] || "_bibliography/").to_s.sub(%r{^/}, "")
bib_path = ROOT.join(source_dir, bibliography)

abort("Bibliography file not found: #{bib_path}") unless bib_path.exist?

bib = BibTeX::Bibliography.parse(bib_path.read, symbolize: true)
bib.replace_strings if scholar["replace_strings"]
bib.join if scholar["join_strings"] && scholar["replace_strings"]

entries = bib.select { |entry| entry.is_a?(BibTeX::Entry) }
sort_keys = Array(scholar["sort_by"] || ["year", "month", "author"]).flatten.map(&:to_s)
entries = sort_entries(entries, sort_keys)

first_names = Array(scholar["first_name"] || []).map(&:to_s)
last_names = Array(scholar["last_name"] || []).map(&:to_s)

first_author_entries = []
co_author_entries = []

entries.each do |entry|
  cv_pub = bib_entry_to_cv_publication(entry)
  if first_author?(entry, first_names, last_names)
    first_author_entries << cv_pub
  else
    co_author_entries << cv_pub
  end
end

sections["First-Author Publications"] = first_author_entries
sections["Co-Author Publications"] = co_author_entries
cv_data["sections"] = sections
normalize_cv_for_pdf!(cv_data)
cv_root["cv"] = cv_data

rendercv_input = build_rendercv_input(cv_root, config)
dated_pdf_name = rendercv_input.delete("_dated_pdf_name")

rendercv_bin = detect_rendercv_bin
abort("RenderCV executable not found. Install dependencies from requirements.txt first.") if rendercv_bin.nil?

FileUtils.mkdir_p(OUTPUT_DIR)

Tempfile.create(["cv.generated", ".yml"], ROOT.join("_data")) do |temp|
  temp.write(rendercv_input.to_yaml)
  temp.flush

  cmd = [rendercv_bin, "render", temp.path, "-o", OUTPUT_DIR.to_s]
  stdout, stderr, status = Open3.capture3(*cmd, chdir: ROOT.to_s)

  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?

  unless status.success?
    abort("RenderCV failed with exit code #{status.exitstatus}")
  end
end

generated_pdf = resolve_pdf_output_path(SETTINGS_PATH)
if generated_pdf && generated_pdf.exist?
  FileUtils.mkdir_p(STABLE_PDF_PATH.dirname)
  FileUtils.cp(generated_pdf, STABLE_PDF_PATH)
  dated_pdf_path = STABLE_PDF_PATH.dirname.join(dated_pdf_name)
  FileUtils.cp(generated_pdf, dated_pdf_path)
  PDF_DATA_PATH.write({
    "path" => "/assets/pdf/#{dated_pdf_name}",
    "filename" => dated_pdf_name,
    "last_updated" => Date.today.strftime("%Y-%m-%d"),
  }.to_yaml)
  puts "Copied #{generated_pdf} -> #{STABLE_PDF_PATH}"
else
  warn "Warning: could not find generated PDF from settings path."
end

puts "Rendered CV PDF successfully in #{OUTPUT_DIR}" 