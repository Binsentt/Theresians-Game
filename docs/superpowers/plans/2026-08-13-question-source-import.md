# Restored Question Source Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import the restored Godot `Questions` DOCX and legacy JSON files into the existing website `learning_files` and `questions` records without making the game read source documents.

**Architecture:** A backend-only utility will discover the verified grade/difficulty folders, parse only explicit four-choice questions with answers, and persist each source file as a normal `fixed_questions` learning file. A SHA-256 source identity is stored on the learning file so reruns skip already-imported source files and never alter teacher records. The existing publish endpoint remains the only route by which database questions reach Godot.

**Tech Stack:** Node.js CommonJS, built-in `fs`, `path`, `crypto`, `zlib`, PostgreSQL through the existing `pg` pool, `node:test`, Godot 4.6.

---

### Task 1: Make source parsing testable

**Files:**
- Create: `Theresian's Quest- Web/capstone/backend/questionSourceImport.utils.js`
- Create: `Theresian's Quest- Web/capstone/backend/questionSourceImport.utils.test.js`

- [ ] **Step 1: Write failing parser tests**

Cover folder metadata normalization (`grade 1/Easy`, `grade 6/Difficult`, `Normal`), legacy wrapped JSON records, explicit DOCX-style labelled choices, unlabeled choices with an explicit correct answer, and malformed records that must be skipped.

- [ ] **Step 2: Run the parser test and confirm the module is missing**

Run: `node --test backend/questionSourceImport.utils.test.js`

Expected: FAIL because `questionSourceImport.utils.js` does not exist.

- [ ] **Step 3: Implement the pure parser module**

Export `discoverQuestionSources`, `parseLegacyJson`, `parseDocxBuffer`, `parseQuestionText`, and `sourceHash`. Use the verified `Easy/Normal/Difficult` names and existing `normalizeDifficultyValue`; extract only questions with non-empty text, at least two choices, and a correct answer that matches one choice. Topic is read only from an explicit `Lesson:` or `Topic:` label.

- [ ] **Step 4: Run the parser test**

Run: `node --test backend/questionSourceImport.utils.test.js`

Expected: PASS with every parser behavior covered.

### Task 2: Add an idempotent import service and command

**Files:**
- Create: `Theresian's Quest- Web/capstone/backend/questionSourceImport.js`
- Create: `Theresian's Quest- Web/capstone/backend/scripts/import-restored-questions.js`
- Create: `Theresian's Quest- Web/capstone/backend/questionSourceImport.test.js`

- [ ] **Step 1: Write failing persistence tests**

Use an in-memory query spy to prove that a new source creates one `learning_files` record and its question records, an existing matching source hash is skipped, and a parse with no valid questions produces a skipped result without inserts.

- [ ] **Step 2: Run the import service test and confirm the service is missing**

Run: `node --test backend/questionSourceImport.test.js`

Expected: FAIL because `questionSourceImport.js` does not exist.

- [ ] **Step 3: Implement persistence and the re-runnable CLI**

The service adds `source_hash` and `import_source_path` to `public.learning_files` if absent, checks `source_hash` before insert, copies accepted source files to the existing `backend/uploads` directory, creates a normal unpublished `fixed_questions` learning file, and inserts question rows with the canonical grade/difficulty/topic. The command defaults to the authoritative Godot `Questions` directory and prints processed/imported/skipped counts.

- [ ] **Step 4: Run the import service test**

Run: `node --test backend/questionSourceImport.test.js`

Expected: PASS, including repeat-run idempotency.

### Task 3: Integrate import metadata with the existing web backend

**Files:**
- Modify: `Theresian's Quest- Web/capstone/backend/server.js`
- Modify: `Theresian's Quest- Web/capstone/backend/server.learningGame.test.js`

- [ ] **Step 1: Write a failing endpoint regression test**

Extend the existing `/api/game/questions` test with an imported-record row and assert it returns game-shaped `id`, `question`, `choices`, `correct_answer`, `grade_level`, `difficulty`, and `math_topic` when published.

- [ ] **Step 2: Run the focused server test**

Run: `node --test backend/server.learningGame.test.js`

Expected: FAIL only if the current query projection omits a required imported-record field.

- [ ] **Step 3: Make the smallest query/schema compatibility change needed**

Keep existing routes and manager behavior. Add the two import metadata columns to startup schema initialization and only adjust the game projection if the test demonstrates a missing field.

- [ ] **Step 4: Run focused backend tests**

Run: `node --test backend/questionSourceImport.utils.test.js backend/questionSourceImport.test.js backend/server.learningGame.test.js`

Expected: PASS.

### Task 4: Verify current Godot runtime and provider compatibility

**Files:**
- Modify only if a fresh normal startup proves a persistent cleanup error: `capstone-theresians-quest/scripts/http_api.gd` or `capstone-theresians-quest/scripts/question_provider.gd`
- Test: existing `capstone-theresians-quest/scripts/godot_diagnostics.gd`, direct headless startup

- [ ] **Step 1: Run project startup without a forced short quit and inspect its log**

Run the Godot executable against `capstone-theresians-quest` and inspect parser/autoload output. Do not change HTTP code for a forced-quit-only leak.

- [ ] **Step 2: Verify QuestionProvider compatibility from source and runtime compile**

Confirm API objects returned by the backend match `_normalize_question` accepted fields, preserve `Data/questions.json` as fallback, and leave `QuizManager` and battle consumers unchanged.

- [ ] **Step 3: Run final checks**

Run backend focused tests, `git diff --check`, direct Godot headless startup, and the scoped diagnostics. Report external PostgreSQL or deployed-backend credentials as blockers rather than inventing them.
