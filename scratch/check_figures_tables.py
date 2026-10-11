import re

with open('scratch/pdf_text.txt', 'r', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

print('=== CHECKING FIGURES AND TABLES ===')

# Find all Figure captions
fig_captions = re.findall(r'(Figure\s+[0-9]+\.[0-9]+[^\n]+)', text)
print('Figure captions found:')
for fc in set(fig_captions):
    print(' ', fc)

# Find all Table captions
tbl_captions = re.findall(r'(Table\s+[0-9]+\.[0-9]+[^\n]+)', text)
print('\nTable captions found:')
for tc in set(tbl_captions):
    print(' ', tc)

# Find all Figure citations in text
fig_refs = re.findall(r'Figure\s+([0-9]+\.[0-9]+)', text)
print('\nFigure reference counts in text:')
for fig in sorted(set(fig_refs)):
    count = fig_refs.count(fig)
    print(f'  Figure {fig}: cited {count} times')

# Find all Table citations in text
tbl_refs = re.findall(r'Table\s+([0-9]+\.[0-9]+)', text)
print('\nTable reference counts in text:')
for tbl in sorted(set(tbl_refs)):
    count = tbl_refs.count(tbl)
    print(f'  Table {tbl}: cited {count} times')
