---
tags: [interview]
---

# Interview preparation

Question banks for five experience levels, plus coding and debugging
challenges. Each chapter of the study path also ends with its own questions;
these banks cut across chapters.

| Bank | Focus | Questions |
|---|---|---:|
| [0 years](01-level-0.md) | Foundations: model, basic SQL, constraints, transactions | 55 |
| [5 years](02-level-5.md) | SQL, PL/SQL, indexing, concurrency, tuning basics | 55 |
| [10 years](03-level-10.md) | Architecture, administration, backup, performance, HA | 55 |
| [15 years](04-level-15.md) | Design: HA/DR, replication, scale, migration, DevOps | 45 |
| [20 years](05-level-20.md) | Strategy, governance, trade-offs, communication | 33 |
| [SQL coding and debugging](06-coding-challenges.md) | Write, fix and read plans for queries on FreshMart data | 28 |

!!! note "About the size of these banks"
    The original brief asked for 700 questions. This edition contains 271
    (plus the questions at the end of every chapter),
    chosen so that each has a specific answer rather than padding the count.
    The format is ready to extend: add questions in the same shape.

## Format

Most entries are a question with a model answer in two to four sentences.
Entries marked :material-star: are worked in full: answer, explanation, SQL or
scenario, follow-up questions, and the common wrong answer.

## How to use the banks

1. Cover the answer. Say yours **aloud**: interviews are spoken.
2. Compare. Mark each question as *known*, *shaky* or *unknown*.
3. For shaky and unknown ones, follow the chapter link and redo the example.
4. Repeat the shaky list after three days.
5. For levels 15 and 20, practice **structure**: clarify the requirement,
   state assumptions, give options with trade-offs, recommend, name the risk.

## What interviewers listen for at each level

| Level | Signal |
|---|---|
| 0 years | Correct definitions; can write and explain a simple query |
| 5 years | Writes non-trivial SQL without help; knows why, not only how; has debugged real problems |
| 10 years | Explains internals; follows a method under pressure; has recovered and tuned production systems |
| 15 years | Compares designs with costs; anticipates failure modes; has led migrations |
| 20 years | Frames decisions for the business; states what would change the recommendation; has lived with long-term consequences |

"I don't know, but here is how I would find out" is a strong answer at every
level. A confident wrong answer about backup or data loss is not.
