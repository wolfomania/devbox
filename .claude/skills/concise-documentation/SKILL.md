---
name: concise-documentation
description: Writes and edits project documentation as concise, fact-only reference material. Use for READMEs, guides, setup instructions, contributor documentation, and other Markdown files.
---

# Concise Documentation

## Rules

- State only verified facts, requirements, actions, constraints, and outcomes.
- Use the fewest words that preserve meaning.
- Use imperative language for instructions.
- Use one fact or action per sentence.
- Prefer bullets for independent points.
- Use numbered lists only for ordered steps.
- Use tables for repeated structured data.
- Use paragraphs only when facts require context.
- Put commands directly after the action they perform.
- Preserve essential setup, usage, behavior, requirements, and limitations.
- Remove opinions, reassurance, marketing, rationale, filler, transitions, and repetition.
- Remove implementation details that the reader does not need.
- Remove information already clear from a heading, command, example, or table.
- Do not add unsupported claims or inferred behavior.
- Verify technical claims against code, configuration, or authoritative sources.

Avoid phrases such as:

- “in order to”
- “please note”
- “it is important to”
- “simply”
- “just”
- “basically”
- “as you can see”
- “this allows you to”

## Editing Process

1. Identify the reader’s required actions and facts.
2. Verify each technical claim.
3. Delete content that does not affect an action, decision, constraint, or result.
4. Merge duplicate information.
5. Shorten every remaining sentence.
6. Check commands, links, names, defaults, and requirements.

## Examples

Before:

> In order to install the application, you can simply run the following command.

After:

> Install:

Before:

> Please note that Docker is required before you can run the tests.

After:

> Requires Docker.

## Final Check

- Is every statement verified?
- Is every word necessary?
- Is any fact repeated?
- Can a paragraph become a list, table, command, or shorter sentence?
