import re
import collections

with open(r'c:\Users\chris\Documents\projects\ContextDrive\scratch\pdf_text.txt', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

print(f"Total pages parsed: {len(pages)-1}")

def analyze_chapter(start_page, end_page, chapter_title):
    print(f"\n=======================================================")
    print(f" ANALYZING: {chapter_title} (Pages {start_page} to {end_page})")
    print(f"=======================================================")
    chap_text = ""
    for p in pages[1:]:
        p_num = int(p.split(' ')[0])
        if start_page <= p_num <= end_page:
            chap_text += f"\n--- Page {p_num} ---\n" + p
    
    # 1. Check double words
    dups = re.findall(r'\b([a-zA-Z]{3,})\s+\1\b', chap_text, re.IGNORECASE)
    if dups:
        print("Duplicate words:", dups)

    # 2. Check spacing before punctuation
    punc_space = re.findall(r'(\w+\s+[,.:;?!])', chap_text)
    if punc_space:
        print("Space before punctuation:", set(punc_space[:10]))

    # 3. Check for malformed contractions or quotes (e.g. system s, vehicle s)
    contractions = re.findall(r'\b\w+\s+[’\']\s*\w+\b', chap_text)
    if contractions:
        print("Spaced contractions:", contractions[:10])

    # 4. Check for typical typos/misspellings
    typos = [
        'seperate', 'occured', 'dependant', 'definately', 'refered', 'enviroment',
        'accelaration', 'vehical', 'proccessing', 'sensetivity', 'implimentation',
        'intigrated', 'platfrom', 'simualtor', 'calibarated', 'distarcting', 'chnages'
    ]
    for typo in typos:
        if typo in chap_text.lower():
            print(f"Found known typo: '{typo}'")

    # 5. Look for incomplete sentences or dangling punctuation
    dangling = re.findall(r'(\b[a-zA-Z]+[,\s]*\n\s*\n\s*[a-z])', chap_text)
    if dangling:
        print("Potential sentence breaks across paragraphs:", len(dangling))

analyze_chapter(1, 10, "Front Matter & Preliminaries")
analyze_chapter(11, 13, "Chapter 1: Introduction")
analyze_chapter(14, 24, "Chapter 2: Literature Survey")
analyze_chapter(25, 30, "Chapter 3: System Analysis")
analyze_chapter(31, 37, "Chapter 4: System Design")
analyze_chapter(38, 45, "Chapter 5: Implementation")
analyze_chapter(46, 49, "Chapter 6: Testing")
analyze_chapter(50, 54, "Chapter 7: Results and Discussion")
analyze_chapter(55, 58, "Chapter 8 & References")
