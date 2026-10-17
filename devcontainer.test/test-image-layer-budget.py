#!/usr/bin/env python3
"""Keep the common developer stack below OverlayFS's image-depth ceiling."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ImageLayerBudgetTest(unittest.TestCase):
    def test_common_developer_stack_leaves_room_for_benches(self):
        # RUN/COPY/ADD/WORKDIR may each contribute a filesystem layer. Count
        # conservatively, including operations that happen to produce no diff.
        # The measured pyBench path adds one Ubuntu layer and six bench layers;
        # reserve additional room for container initialization/writable layers.
        recipes = ('base-image/Dockerfile', 'devBenches/base-image/Dockerfile',
                   'user-layer/Dockerfile')
        counts = {name: len(re.findall(r'^\s*(?:RUN|COPY|ADD|WORKDIR)\b',
                                      (ROOT / name).read_text(), re.MULTILINE | re.IGNORECASE))
                  for name in recipes}
        self.assertLessEqual(sum(counts.values()), 114,
                             f'Developer image stack leaves too few layers for a bench: {counts}')


if __name__ == '__main__':
    unittest.main()
