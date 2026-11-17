# Stage 4 · Principal

**For:** principal engineers and database leads (roughly the 15-year level).
**Time:** about 8 weeks. **Prerequisite:** you have operated production databases.

The question changes from "how do I do it?" to "which design, and what does it cost?".
Every chapter in this stage ends with trade-offs and failure scenarios.

## Reading order

1. [4.1 HA and DR architecture](../high-availability/03-ha-dr-architecture.md)
2. [4.2 GoldenGate and replication](../high-availability/04-goldengate-replication.md)
3. [4.3 Distributed databases and sharding](../distributed-databases/01-distributed.md)
4. [4.4 Scalability features](../performance-engineering/04-scalability-features.md)
5. [4.5 Data movement and integration](../data-integration/01-data-integration.md)
6. [4.6 Data warehousing](../data-warehousing/01-data-warehousing.md)
7. [4.7 Oracle AI Database 26ai](../oracle-26ai/01-oracle-26ai.md)
8. [4.8 Spring Boot and Oracle](../spring-boot-integration/01-spring-boot.md)
9. [4.9 Database DevOps](../database-devops/01-devops.md)

## Exit test

- [ ] For a given RTO and RPO, choose between RAC, Data Guard, GoldenGate or a combination, and justify the cost.
- [ ] Design a zero-downtime migration from 19c on-premises to 26ai in the cloud.
- [ ] Explain why a distributed transaction across two microservices is usually the wrong design, and what replaces it.
- [ ] Review the FreshMart [scaling tiers](../grocery-application/05-scaling.md) and argue against one of the choices.
