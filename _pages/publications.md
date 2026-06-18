---
layout: page
permalink: /publications/
title: Publications
description: Publications listed in reverse chronological order.
nav: true
nav_order: 4
---

<!-- _pages/publications.md -->

<div class="publications">
  {% assign bib_entries = site.data.bib_publications.all | default: empty_array %}

  {% if bib_entries == blank or bib_entries.size == 0 %}
    {% bibliography %}
  {% else %}
    {% assign publication_groups = bib_entries | group_by: "year" | sort: "name" | reverse %}
    {% for group in publication_groups %}
      <h2 class="mt-4">{{ group.name }}</h2>
      <ul class="list-unstyled">
        {% for entry in group.items %}
          <li class="mb-3">
            <p class="mb-1">
              {% if entry.authors %}
                <strong>
                  {% assign highlighted_authors = "" %}
                  {% for author in entry.authors %}
                    {% if author contains "Burnham" or author contains "burnham" %}
                      {% capture author_html %}<span style="color: var(--global-theme-color);">{{ author }}</span>{% endcapture %}
                    {% else %}
                      {% capture author_html %}{{ author }}{% endcapture %}
                    {% endif %}
                    {% if forloop.first %}
                      {% assign highlighted_authors = author_html %}
                    {% else %}
                      {% assign highlighted_authors = highlighted_authors | append: "; " | append: author_html %}
                    {% endif %}
                  {% endfor %}
                  {{ highlighted_authors }}
                </strong>
              {% endif %}
              {% if entry.year %} ({{ entry.year }}).{% endif %}
              {% if entry.title %} {{ entry.title }}.{% endif %}
              {% if entry.venue %} <em>{{ entry.venue }}</em>{% endif %}
              {% if entry.volume %}, {{ entry.volume }}{% endif %}
              {% if entry.number %}({{ entry.number }}){% endif %}
              {% if entry.pages %}, {{ entry.pages }}{% endif %}.
            </p>
            {% if entry.ads_url %}
              <p class="mb-0">
                <a href="{{ entry.ads_url }}" target="_blank" rel="noopener noreferrer">View publication</a>
              </p>
            {% elsif entry.url %}
              <p class="mb-0">
                <a href="{{ entry.url }}" target="_blank" rel="noopener noreferrer">View publication</a>
              </p>
            {% endif %}
          </li>
        {% endfor %}
      </ul>
    {% endfor %}
  {% endif %}
</div>
