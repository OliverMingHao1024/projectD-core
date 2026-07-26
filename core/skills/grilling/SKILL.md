---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any grill trigger phrases.
---

# Grilling

Interview the user relentlessly about every aspect until reaching a shared
understanding. Walk down each branch of the decision tree, resolving dependencies
between decisions one by one. For each question, provide a recommended answer.

Ask questions one at a time and wait for feedback before continuing. Do not ask
multiple questions at once.

If a fact can be found by exploring the environment, look it up instead of asking.
The decisions belong to the user: present each material decision and wait for an
answer.

Do not act on the subject being grilled until the user confirms shared understanding.
Follow higher-priority project governance and approval boundaries throughout.

When the confirmed subject is a software change and the user authorizes execution,
continue with this compact engineering flow unless a higher-priority rule or the
user's current instruction changes it:

1. Synthesize the confirmed conversation into a concise local spec.
2. Agree on the highest practical public test seam.
3. Implement one tracer-bullet slice at a time with red → green TDD.
4. Run type checking, builds, focused tests, then the full relevant suite.
5. Review the final diff separately against repository standards and the spec.
6. Commit only after both review axes and required verification are addressed.

Treat this as a subordinate, composable workflow. Project constitution, nearer
repository rules, and the user's current explicit instructions always take
precedence. Do not apply the engineering flow to non-software grilling.

## Source

Adapted for cross-agent discovery from
<https://github.com/mattpocock/skills/tree/ed37663cc5fbef691ddfecd080dff42f7e7e350d/skills/productivity/grilling>.
Licensed under MIT; see [LICENSE](LICENSE).
