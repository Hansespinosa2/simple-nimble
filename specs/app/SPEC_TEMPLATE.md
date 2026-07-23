# Specification Template

Use this template for any new bounded feature or subsystem spec.

```markdown
# Specification: [Capability name]

> **Spec type:** [Product/feature | Domain/data | Workflow | Collaboration | Evaluation]
> **Status:** [Draft | Ready for implementation | Superseded]
> **Decision owner:** [name]
> **Primary executor:** [AI agent | engineer | designer | cross-functional]
> **Last updated:** [YYYY-MM-DD]

---

## 1. Why this spec exists

[One paragraph: what product or execution problem this spec resolves.]

## 2. Outcome statement

**After this spec is executed:**
[One sentence describing the observable change.]

**Verification method:**
[How an outsider confirms the outcome.]

## 3. Known decisions

| Decision | Status | Notes |
|---|---|---|
| [decision] | [Validated / Assumed / Unknown: TBD] | [source, owner, or follow-up] |

## 4. In scope

| ID | Capability | Notes |
|---|---|---|
| [S-1] | [capability] | [details] |

## 5. Out of scope

| ID | Exclusion | Why excluded |
|---|---|---|
| [X-1] | [named adjacent capability] | [rationale] |

## 6. Actors and roles

| Actor | Goal | Notes |
|---|---|---|
| [actor] | [goal] | [constraints] |

## 7. Flow / state changes

[Ordered steps, decision points, or state transitions.]

## 8. Acceptance criteria

| ID | Type | Criterion | Status |
|---|---|---|---|
| AC-1 | Behavioral | [binary-testable criterion] | [Validated / Assumed / Unknown: TBD] |

Include:
- at least one negative criterion
- at least one edge-case criterion where relevant
- at least one dependency criterion if external systems are involved

## 9. Failure conditions

| ID | Assumption at risk | Deviation signal | Action |
|---|---|---|---|
| FC-1 | [assumption] | [observable signal] | [stop/adjust/escalate] |

## 10. Dependencies

| Dependency | Type | Status | Notes |
|---|---|---|---|
| [dependency] | [technical/product/content] | [ready/in-progress/blocked/unknown] | [notes] |

## 11. Open questions / TBDs

| ID | Question | Why it matters | Owner |
|---|---|---|---|
| TBD-1 | [question] | [impact] | [owner] |

## 12. Evaluation hooks

- [Golden scenario or fixture]
- [UI journey or system test]
- [Rules assertion]
- [Coverage check]
```
