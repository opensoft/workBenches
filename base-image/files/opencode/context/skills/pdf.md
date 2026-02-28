# Skill: PDF Manipulation

## Triggers
- Extracting text/tables from PDFs
- Creating new PDF documents
- Merging/splitting PDFs
- Filling PDF forms
- Processing PDFs at scale

## Capabilities

### Text Extraction
```python
import pdfplumber

with pdfplumber.open("document.pdf") as pdf:
    for page in pdf.pages:
        text = page.extract_text()
        tables = page.extract_tables()
```

### Table Extraction
```python
import camelot

# For bordered tables
tables = camelot.read_pdf("document.pdf", flavor="lattice")

# For borderless tables
tables = camelot.read_pdf("document.pdf", flavor="stream")
```

### PDF Creation
```python
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter

c = canvas.Canvas("output.pdf", pagesize=letter)
c.drawString(100, 750, "Hello World")
c.save()
```

### Form Filling
```python
from PyPDF2 import PdfReader, PdfWriter

reader = PdfReader("form.pdf")
writer = PdfWriter()
writer.append(reader)
writer.update_page_form_field_values(
    writer.pages[0],
    {"field_name": "value"}
)
```

### Merge/Split
```python
from PyPDF2 import PdfMerger, PdfReader, PdfWriter

# Merge
merger = PdfMerger()
merger.append("doc1.pdf")
merger.append("doc2.pdf")
merger.write("merged.pdf")

# Split
reader = PdfReader("document.pdf")
for i, page in enumerate(reader.pages):
    writer = PdfWriter()
    writer.add_page(page)
    writer.write(f"page_{i}.pdf")
```

## Key Libraries
- `pdfplumber`: Best for text/table extraction
- `camelot-py`: Specialized table extraction
- `PyPDF2`: Manipulation, merging, splitting
- `reportlab`: PDF creation
- `pdfrw`: Low-level PDF operations
