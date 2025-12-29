# Skill: Creating New Skills

## Triggers
- User wants to create a new skill
- Updating an existing skill
- Extending agent capabilities
- Adding specialized knowledge or workflows

## Skill Structure

A skill context file should contain:

```markdown
# Skill: [Name]

## Triggers
- When this skill should be activated
- Keywords or patterns to match
- Task types this skill handles

## Capabilities
- What this skill enables
- Core functionality
- Limitations

## Workflow
1. Step-by-step process
2. Decision points
3. Validation steps

## Examples
- Code samples
- Common patterns
- Best practices

## Tools & Resources
- Required libraries
- External dependencies
- Reference materials
```

## Creating a New Skill

### 1. Identify the Need
- What task does this skill address?
- When should agents use it?
- What knowledge is required?

### 2. Define Triggers
- Clear activation conditions
- Keywords users might say
- Task patterns to match

### 3. Document the Workflow
- Step-by-step instructions
- Decision trees if needed
- Error handling

### 4. Add Examples
- Working code samples
- Common use cases
- Edge cases

### 5. Test the Skill
- Verify trigger matching
- Test workflow completeness
- Validate examples work

## File Location
Save to: `~/.config/opencode/context/skills/<skill-name>.md`

## Update Index
Add entry to: `~/.config/opencode/context/skills/index.md`
