import re

with open('scratch/pdf_text.txt', 'r', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

print('=== SCANNING ALL PAGES FOR STRAIGHT QUOTES (") ===')
for p in range(1, len(pages)):
    lines = pages[p].split('\n')
    for l in lines:
        if '"' in l:
            print(f'Page {p}: {l.strip()}')
