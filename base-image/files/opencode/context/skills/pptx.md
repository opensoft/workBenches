# Skill: PowerPoint Presentation Handling

## Triggers
- Creating new presentations
- Modifying .pptx content
- Working with slide layouts
- Adding speaker notes or comments
- Presentation analysis

## Capabilities

### Create Presentation
```python
from pptx import Presentation
from pptx.util import Inches, Pt

prs = Presentation()

# Title slide
slide_layout = prs.slide_layouts[0]
slide = prs.slides.add_slide(slide_layout)
title = slide.shapes.title
subtitle = slide.placeholders[1]
title.text = "Presentation Title"
subtitle.text = "Subtitle here"

# Content slide
slide_layout = prs.slide_layouts[1]
slide = prs.slides.add_slide(slide_layout)
slide.shapes.title.text = "Slide Title"

prs.save("presentation.pptx")
```

### Add Content
```python
# Add text box
from pptx.util import Inches

left = Inches(1)
top = Inches(2)
width = Inches(8)
height = Inches(1)
txBox = slide.shapes.add_textbox(left, top, width, height)
tf = txBox.text_frame
tf.text = "Text content"

# Add image
slide.shapes.add_picture("image.png", Inches(1), Inches(1))

# Add table
rows, cols = 3, 4
table = slide.shapes.add_table(rows, cols, left, top, width, height).table
table.cell(0, 0).text = "Header"
```

### Speaker Notes
```python
slide.notes_slide.notes_text_frame.text = "Speaker notes here"
```

### Read Existing
```python
prs = Presentation("existing.pptx")
for slide in prs.slides:
    for shape in slide.shapes:
        if shape.has_text_frame:
            print(shape.text)
```

## Key Library
- `python-pptx`: Primary library for PowerPoint manipulation

## Best Practices
- Use slide layouts for consistency
- Keep text minimal on slides
- Use high-resolution images
- Add comprehensive speaker notes
- Test on target display resolution
