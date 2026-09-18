# Model Routing Policy

The main agent acts as the orchestrator.

## Delegate to cheaper agents

Use Luna for:
- repository searches
- finding files, symbols, functions and references
- reading GitHub Actions logs
- extracting compiler errors
- checking workflow results
- simple verification
- summarizing large logs
- 

Use Terra for:
- simple Swift fixes
- mechanical code changes
- repetitive edits
- small UI changes
- straightforward compiler errors

## Main agent

Use Sol for:
- normal feature implementation
- SwiftUI implementation
- moderate debugging
- changes involving multiple related files
- integrating delegated results

Do not perform work yourself when it can reliably be delegated
to Luna or Terra.

## Astra escalation

Astra should only be used when:
- Sol has already attempted the problem and failed
- the root cause remains unclear after targeted investigation
- the bug involves complex AVFoundation behavior
- the bug involves concurrency or difficult runtime behavior
- multiple subsystems interact in a way requiring deep reasoning
- an architectural decision requires deeper analysis

Do NOT use Astra for:
- repository exploration
- searching
- reading logs
- compiler error extraction
- workflow monitoring
- simple Swift fixes
- routine feature implementation
- verification

## Build workflow

For each feature:

1. Luna locates relevant code.
2. Sol determines implementation.
3. Terra may perform simple/mechanical edits.
4. Sol handles substantial implementation.
5. GitHub Actions performs compilation/testing/IPA generation.
6. If build fails, Luna extracts only the relevant errors.
7. Terra handles obvious compiler fixes.
8. Sol handles non-trivial fixes.
9. Run GitHub Actions again.
10. Escalate to Astra only if targeted Sol attempts fail.

Never send an entire build log to Astra.
Never ask Astra to explore the entire repository.
