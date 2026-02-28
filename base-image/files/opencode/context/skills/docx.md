# Skill: DOCX Document Handling

## Triggers
- Working with .docx files
- Creating new Word documents
- Modifying or editing document content
- Working with tracked changes
- Adding comments to documents

## Capabilities

### Creation
- Create new .docx documents with proper formatting
- Apply styles, headings, and structure
- Add tables, lists, and images

### Editing
- Modify existing document content
- Preserve original formatting
- Handle tracked changes
- Add/remove comments

### Analysis
- Extract text content
- Read document structure
- Parse tables and lists
- Identify formatting patterns

## Tools & Libraries

### Python
```python
from docx import Document
from docx.shared import Inches, Pt

# Create new document
doc = Document()
doc.add_heading('Title', 0)
doc.add_paragraph('Content here')
doc.save('output.docx')

# Read existing
doc = Document('input.docx')
for para in doc.paragraphs:
    print(para.text)
```

### Key Packages
- `python-docx`: Primary library for .docx manipulation
- `mammoth`: Convert .docx to HTML
- `pandoc`: Universal document converter

## Best Practices
- Always preserve original when editing (work on copy)
- Use styles instead of direct formatting
- Handle encoding properly for special characters
- Validate document structure after modifications
