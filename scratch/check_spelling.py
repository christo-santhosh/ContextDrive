import re

with open('scratch/pdf_text.txt', 'r', encoding='utf-8') as f:
    text = f.read()

pages = text.split('=== PAGE ')

# Let's inspect potential spelling mistakes by checking common misspelling patterns
common_typos = {
    'telematic': 'telemetric',
    'accelaration': 'acceleration',
    'accelration': 'acceleration',
    'seperate': 'separate',
    'occured': 'occurred',
    'dependant': 'dependent',
    'calibarated': 'calibrated',
    'simualtor': 'simulator',
    'vehical': 'vehicle',
    'proccess': 'process',
    'intergration': 'integration',
    'implimentation': 'implementation',
    'compatability': 'compatibility',
    'maintainance': 'maintenance',
    'resposive': 'responsive',
    'detials': 'details',
    'distarcting': 'distracting',
    'chnages': 'changes',
    'genereated': 'generated',
    'mjust': 'must',
    'mistkes': 'mistakes',
    'infront': 'in front',
    'alot': 'a lot',
    'everytime': 'every time',
    'nowdays': 'nowadays'
}

for i, p in enumerate(pages[1:], 1):
    p_lower = p.lower()
    for typo, correction in common_typos.items():
        if typo in p_lower:
            matches = re.findall(rf'\b{typo}\b', p_lower)
            if matches:
                print(f'Page {i}: Found typo "{typo}" -> should be "{correction}"')
