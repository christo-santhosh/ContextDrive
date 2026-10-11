import re

with open('scratch/pdf_text.txt', 'r', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

print('=== SCANNING CHAPTER 2 (Pages 14 to 24) ===')
for p in range(14, 25):
    lines = pages[p].split('\n')
    for l in lines:
        # Check for citation formatting
        if re.search(r'\b[A-Z][a-z]+\s+et\s+al\b', l) and 'et al.' not in l:
            print(f'Page {p}: Missing period after et al: {l.strip()}')
        # Check for unclosed quotes
        quotes_single = l.count("'") + l.count("’") + l.count("‘")
        # Check for double quotes
        if '"' in l:
            print(f'Page {p}: Straight double quote found (use LaTeX `` \'\'): {l.strip()}')
        # Check for passive awkward phrases
        if 'is been' in l.lower() or 'has been being' in l.lower():
            print(f'Page {p}: Grammatical flaw: {l.strip()}')
