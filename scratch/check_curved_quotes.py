import re

with open('scratch/pdf_text.txt', 'r', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

print('=== SCANNING CURVED AND SPECIAL QUOTES ===')
for p in range(1, len(pages)):
    lines = pages[p].split('\n')
    for l in lines:
        if any(c in l for c in ['“', '”', '‘', '’', '`']):
            # let's see which lines have odd quotes
            if '“' in l or '”' in l:
                print(f'Page {p} (double curved): {l.strip()[:100]}')
