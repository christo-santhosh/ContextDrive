import pymupdf
import sys
import os

pdf_path = r"c:\Users\chris\Documents\projects\ContextDrive\project report\first_review.pdf"
out_dir = r"c:\Users\chris\Documents\projects\ContextDrive\project report\ContextDrive_Report\img"

pages_to_extract = {
    18: "arch_diagram.png",
    19: "use_case_diagram.png",
    20: "dfd_0.png",
    21: "dfd_1.png",
    22: "dfd_2.png",
    23: "gantt_chart.png"
}

doc = pymupdf.open(pdf_path)

for page_num, filename in pages_to_extract.items():
    page = doc.load_page(page_num)
    # We can crop the page slightly to remove headers/footers if we want, or just keep it as is.
    # The rect is the full page. Let's just render the whole page for simplicity, it looks like a slide.
    # Increase zoom for higher quality
    zoom = 2.0
    mat = pymupdf.Matrix(zoom, zoom)
    
    # We can crop out the top bar and bottom bar of the slide.
    # The slide is 1024x768 approx (or 16:9).
    rect = page.rect
    # 5% from top and 10% from bottom can be cropped.
    clip = pymupdf.Rect(rect.x0, rect.y0 + rect.height * 0.1, rect.x1, rect.y1 - rect.height * 0.05)
    
    pix = page.get_pixmap(matrix=mat, clip=clip)
    out_path = os.path.join(out_dir, filename)
    pix.save(out_path)
    print(f"Saved {out_path}")

print("Done")
