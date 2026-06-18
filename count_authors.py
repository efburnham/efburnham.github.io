import collections
import re

# Path to your bibliography file
bib_file_path = '_bibliography/papers.bib'

# Dictionaries to track data
# author_counts: { lastname_lowercase: frequency_count }
# coauthors_data: { lastname_lowercase: { (proper_lastname, firstname) } }
author_counts = collections.Counter()
coauthors_data = collections.defaultdict(set)

# Regular expression to match 'author = { ... }' or 'author = "..."'
author_regex = re.compile(r'author\s*=\s*[\{\"](.*?)[\}\"]', re.IGNORECASE | re.DOTALL)

try:
    with open(bib_file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find all author blocks in the file
    author_blocks = author_regex.findall(content)
    
    for block in author_blocks:
        clean_block = " ".join(block.split())
        authors = clean_block.split(' and ')
        
        for author in authors:
            author = author.strip()
            if not author:
                continue
                
            # Handle standard BibTeX "Last, First" format
            if ',' in author:
                parts = author.split(',', 1)
                last = parts[0].strip()
                first = parts[1].strip()
            # Handle "First Last" format fallback
            else:
                parts = author.rsplit(' ', 1)
                if len(parts) == 2:
                    first, last = parts[0].strip(), parts[1].strip()
                else:
                    last = author
                    first = ""
            
            # Change 'yourlastname' to your actual lowercase last name to exclude yourself
            if last.lower() == 'burnham': 
                continue
                
            if last and first:
                last_lower = last.lower()
                coauthors_data[last_lower].add((last, first))
                author_counts[last_lower] += 1

    # Print the custom YAML format sorted by most frequent to least frequent
    print("\nCOPY AND PASTE THIS INTO _data/coauthors.yml:")
    print("# Sorted from most frequent to least frequent collaborator")
    print("="*50)
    
    # Sort keys based on their counted frequencies (highest first)
    sorted_by_frequency = author_counts.most_common()
    
    for last_lower, count in sorted_by_frequency:
        name_tuples = coauthors_data[last_lower]
        proper_last = list(name_tuples)[0][0]
        
        # Gather and clean all unique first name variations
        firstnames = sorted(list(set(t[1] for t in name_tuples)))
        names_str = ", ".join(f'"{n}"' for n in firstnames)
        
        # Build the fallback URL
        fallback_url = f"https://scholar.google.com/scholar?q={proper_last}+{firstnames[0]}"
        
        # Display entry with a comment showing the paper count for verification
        print(f'# Appears on {count} paper(s)')
        print(f'"{last_lower}":')
        print(f'  - firstname: [{names_str}]')
        print(f'    url: {fallback_url}\n')

except FileNotFoundError:
    print(f"❌ Error: Could not find the file at '{bib_file_path}'.")