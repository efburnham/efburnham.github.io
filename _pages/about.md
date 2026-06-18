---
layout: about
title: About
permalink: /
nav: true
nav_order: 1
subtitle: '<span style="color: var(--global-theme-color);">“Science makes people reach selflessly for truth and objectivity; it teaches people to accept reality, with wonder and admiration, not to mention the deep awe and joy that the natural order of things brings to the true scientist.” ― Lise Meitner</span>'

profile:
  align: right
  image: prof_pic.jpg
  image_circular: true # crops the image to make it circular
  # more_info: >
  #   <p>445A Davey Lab</p>
  #   <p>University Park, PA 16802, USA</p>

selected_papers: false # custom selected publications block rendered below
social: true # includes social icons at the bottom of the page

announcements:
  enabled: true # includes a list of news items
  scrollable: true # adds a vertical scroll bar if there are more than 3 news items
  limit: 5 # leave blank to include all the news in the `_news` folder

latest_posts:
  enabled: false
  scrollable: true # adds a vertical scroll bar if there are more than 3 new posts items
  limit: 3 # leave blank to include all the blog posts
---

I am a PhD student in Astronomy and Astrophysics at Penn State University, where I study galaxy formation and evolution under the supervision of Dr. Joel Leja. My research focuses on using **statistical inference and machine learning to understand the physical properties of galaxies from their spectra,** both as individual systems and as entire populations.

This work is driven by a new generation of astronomical surveys. Space-based observatories such as the James Webb Space Telescope (JWST) allow us to probe the earliest galaxies during cosmic dawn, while next-generation ground-based instruments such as the Prime Focus Spectrograph (PFS) will provide an unprecedented view of galaxy evolution during cosmic noon. To meet the challenges posed by these large datasets, **I develop accelerated software tools** that enable astronomers to efficiently infer the histories and physical properties of millions of galaxies.

I am a member of the PFS Galaxy Evolution (GE) collaboration. With its remarkable multiplexing capabilities, PFS GE will obtain **spectra for more than half a million galaxies spanning roughly six billion years of cosmic time**. As part of the low-redshift working group, I help develop the data pipeline that will fit these observations and create large catalogs of stellar population properties, enabling new studies of galaxy evolution on a population-level scale.

A central focus of my research is understanding the **burstiness of star formation in high-redshift galaxies**. In particular, I am interested in how we can quantify this behavior and designing future JWST surveys capable of measuring this robustly.

Outside of astronomy, I enjoy spending hours experimenting in the kitchen, reading books far too large to in my bag, and writing stories of my own.



## Selected Publications

{% assign selected_entries = site.data.bib_publications.all | where: "selected", true %}
{% if selected_entries and selected_entries.size > 0 %}
<ul class="list-unstyled">
  {% for entry in selected_entries %}
    <li class="mb-4">
      <p class="mb-1" style="font-size: 1.1rem; line-height: 1.5;">
        {% if entry.ads_url %}
          <a href="{{ entry.ads_url }}" target="_blank" rel="noopener noreferrer" style="color: var(--global-theme-color); font-size: 1.1rem; font-weight: 600; text-decoration: none;"><strong>{{ entry.title }}</strong></a>
        {% elsif entry.url %}
          <a href="{{ entry.url }}" target="_blank" rel="noopener noreferrer" style="color: var(--global-theme-color); font-size: 1.1rem; font-weight: 600; text-decoration: none;"><strong>{{ entry.title }}</strong></a>
        {% else %}
          <strong style="font-size: 1.1rem;">{{ entry.title }}</strong>
        {% endif %}
        {% if entry.year %} ({{ entry.year }}).{% endif %}
      </p>
      {% if entry.selected_image %}
        <figure class="mt-2 mb-0">
          <img src="{{ entry.selected_image | relative_url }}" alt="Example figure for {{ entry.title }}" class="img-fluid rounded">
          {% if entry.selected_image_caption %}
            <figcaption class="text-muted mt-1" style="font-size: 0.85rem; line-height: 1.4;">{{ entry.selected_image_caption }}</figcaption>
          {% endif %}
        </figure>
      {% endif %}
    </li>
  {% endfor %}
</ul>
{% else %}
<p>No selected publications are marked yet. Add <code>selected={true}</code> in <code>_bibliography/papers.bib</code> to feature papers here.</p>
{% endif %}

