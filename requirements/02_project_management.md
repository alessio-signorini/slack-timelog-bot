# Requirement: Project Management

## Description

The bot must maintain a list of known projects and allow users to select from them or create new ones when logging time.

## Known Projects (Initial)

- Lion
- Pascal
- Waterfall
- Pfizer Nurtec
- Consumer
- Proteomic Pilot
- AHA

## Fuzzy Matching

When a user mentions a project, the LLM should:
1. Attempt to match against known projects (case-insensitive)
2. Handle common variations (e.g., "Nutella" → "Ferrero Nutella")
3. Provide a confidence score (0-100)

## Project Selection Flow

When confidence < 70%:

1. Bot posts ephemeral message with dropdown
2. Dropdown contains all known projects + "Create New Project" option
3. If user selects a project, time entry is created with that project
4. If user selects "Create New Project", modal opens with text input
5. Modal is pre-populated with suggested project name from LLM

## Acceptance Criteria

- [x] All initial projects are seeded in database
- [x] Fuzzy matching works for common variations
- [x] Low-confidence triggers interactive dropdown
- [x] "Create New Project" opens modal
- [x] Modal pre-populates with suggested name
- [x] New project is persisted after creation
- [x] Time entries are created after project selection
