# Data model

No new persisted entities. Inputs are the original Claude argv, inherited `CLAUDE_CODE_EFFORT_LEVEL`, and selected profile settings `env.CLAUDE_CODE_EFFORT_LEVEL`. Output is the existing startup flags array, optionally extended with `--effort xhigh`. Existing model/effort settings remain unchanged.
