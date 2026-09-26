# ADR 0005: AI agent conduct and multi-agent workflow

- Status: Accepted
- Date: 2026-09-26
- Deciders: maintainer (eywitteveen)

## Context

Multiple coding assistants and AI agents (including Claude Code, Cursor, Windsurf, Aider, GitHub Copilot, and Gemini / Antigravity) collaborate on this repository across different machines, platforms, and sessions. During development, assistants may default to opportunistic or hasty behavior—such as creating ad-hoc local scratch files for tracking tasks or issues instead of using the repository's GitHub project infrastructure, pushing directly to `main`, introducing unverified changes or unnecessary AI co-author trailers, and skipping verification runs.

To ensure consistency, reproducibility, code quality, and alignment across sessions and tools, explicit principles are required for all AI agents working on this codebase.

## Decision

All AI agents working on `dawo-appliance` must observe the following principles:

1. **GitHub as the Single Source of Truth:**
   - Issues, task backlogs, discussions, and decision tracking must exclusively live on GitHub (`github.com/EduardWitteveen/dawo-appliance`).
   - Do not create local scratch, todo, or issue markdown files in the repository for items that belong in GitHub issues.
   - Never push directly to `main`. Every change must follow the GitHub workflow: issue first, feature branch from `origin/main`, Conventional Commits, pull request, verification, and rebase merge.

2. **Investigative and Thoughtful over Hasty Action:**
   - Always conduct thorough research into existing project structure, upstream relationships, and documentation before proposing or applying code changes.
   - Do not rush to push speculative code. Consider the broader architecture, verify assumptions, and distinguish blocking problems from later improvements.
   - Ask clarifying questions when requirements are ambiguous or when multiple choices lead to materially different outcomes.

3. **Repository Standards & Conventions:**
   - **Language:** All repository content—code, comments, documentation, pull requests, and commit messages—is in **English**. Conversation with the maintainer may be in Dutch.
   - **Commits:** Conventional Commits in logical steps.
   - **Authorship:** Commit author must be the maintainer's GitHub noreply address (`6449834+EduardWitteveen@users.noreply.github.com`).
   - **No AI attribution:** Do not add AI trailers (`Co-Authored-By: Claude`, `Generated with Aider`, etc.) to commit messages.

4. **Non-Destructive by Default & Safety:**
   - Follow the safety model: destructive disk actions require an explicit target device and confirmation flags.
   - Do not make host/WSL system modifications without maintainer approval.
   - Never commit secrets, passwords, or private keys.

5. **Cross-Agent Standards Entrypoint (`AGENTS.md`):**
   - Provide a root `AGENTS.md` specifying these rules and operational procedures as the universal standard recognized across diverse AI tools.
   - `AGENTS.md` serves as the sole canonical standard; tool-specific files (such as `CLAUDE.md`) are retired to eliminate duplication.

## Consequences

- AI agents will take an extra moment to investigate, check existing issues, and verify tests, but changes will be deliberate, robust, and aligned with repository standards.
- Clear separation between repository artifacts (English, strictly formatted) and human discussion (Dutch).
- Clean Git history without tool-specific noise or scattered uncommitted notes.
