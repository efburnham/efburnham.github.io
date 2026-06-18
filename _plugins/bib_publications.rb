require "bibtex"
require "uri"

module Jekyll
  class BibPublicationsGenerator < Generator
    safe true
    priority :low

    def generate(site)
      config = site.config["scholar"] || {}
      bibliography = config["bibliography"] || "papers.bib"
      source_dir = (config["source"] || "_bibliography/").sub(%r{^/}, "")
      bib_path = File.expand_path(File.join(site.source, source_dir, bibliography))
      return unless File.exist?(bib_path)

      bib = BibTeX::Bibliography.parse(File.read(bib_path), symbolize: true)
      bib.replace_strings if config["replace_strings"]
      bib.join if config["join_strings"] && config["replace_strings"]

      entries = bib.select { |entry| entry.is_a?(BibTeX::Entry) }
      entries = sort_entries(entries, config)

      site.data["bib_publications"] = {
        "all" => entries.map { |entry| entry_attributes(entry) },
        "first_author" => [],
        "co_author" => [],
      }

      first_names = Array(config["first_name"] || []).map(&:to_s)
      last_names = Array(config["last_name"] || []).map(&:to_s)

      entries.each do |entry|
        attrs = entry_attributes(entry)
        if first_author?(entry, first_names, last_names)
          site.data["bib_publications"]["first_author"] << attrs
        else
          site.data["bib_publications"]["co_author"] << attrs
        end
      end
    rescue StandardError => e
      Jekyll.logger.warn "BibPublicationsGenerator:", "Failed to build bibliography data: #{e.message}"
    end

    private

    def sort_entries(entries, config)
      entries.sort do |a, b|
        compare_entries(a, b, config)
      end
    end

    def compare_entries(a, b, config)
      sort_keys = Array(config["sort_by"] || ["year", "month", "author"]).flatten
      sort_keys.map do |key|
        compare_key(a, b, key.to_s)
      end.find { |result| result != 0 } || 0
    end

    def compare_key(a, b, key)
      case key
      when "year"
        b[:year].to_i <=> a[:year].to_i
      when "month"
        month_value(b[:month]) <=> month_value(a[:month])
      when "author"
        normalize_author(a[:author].to_s) <=> normalize_author(b[:author].to_s)
      else
        normalize_value(b[key].to_s) <=> normalize_value(a[key].to_s)
      end
    end

    def normalize_author(value)
      normalize_value(value)
    end

    def normalize_value(value)
      value.to_s.strip.downcase
    end

    def month_value(value)
      month = value.to_s.strip.downcase
      return month.to_i if month =~ /^\d+$/

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

      month_names.each do |key, value|
        return value if month.start_with?(key)
      end

      0
    end

    def entry_attributes(entry)
      authors = entry[:author] ? entry[:author].to_a.map(&:to_s) : []
      {
        "id" => entry.key.to_s,
        "title" => entry[:title].to_s,
        "authors" => authors,
        "venue" => publication_venue(entry),
        "year" => entry[:year].to_s,
        "volume" => entry[:volume].to_s,
        "number" => entry[:number].to_s,
        "pages" => entry[:pages].to_s,
        "doi" => entry[:doi].to_s,
        "eprint" => entry[:eprint].to_s,
        "url" => entry[:url].to_s,
        "ads_url" => entry[:ads_url].to_s,
        "publisher" => entry[:publisher].to_s,
        "selected" => truthy_bibtex_value?(entry[:selected]),
        "selected_image" => entry[:selected_image].to_s,
        "selected_image_caption" => entry[:selected_image_caption].to_s,
      }
    end

    def truthy_bibtex_value?(value)
      value.to_s.strip.downcase == "true"
    end

    def publication_venue(entry)
      entry[:journal].to_s.presence || entry[:booktitle].to_s.presence || entry[:series].to_s.presence || entry[:publisher].to_s
    end

    def first_author?(entry, first_names, last_names)
      return false if first_names.empty? || last_names.empty?
      return false unless entry[:author]

      authors = entry[:author].to_a.map(&:to_s).compact
      first_author = authors.first
      return false unless first_author

      author_matches_self?(first_author, first_names, last_names)
    end

    def author_matches_self?(author, first_names, last_names)
      normalized = normalize_name(author)
      normalized_first_names = first_names.flat_map { |name| [name.to_s.strip, name.to_s.strip[0]] }.compact.map(&:downcase)
      normalized_last_names = last_names.map { |name| name.to_s.strip.downcase }

      normalized_last_names.any? do |last|
        normalized.include?(last) && normalized_first_names.any? { |first| normalized.include?(first.downcase) }
      end
    end

    def normalize_name(value)
      value.to_s.gsub(/[^\p{Alnum}\s]/, ' ').strip.downcase
    end

  end
end
