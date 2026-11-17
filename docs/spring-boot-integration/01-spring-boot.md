---
tags: [stage-4, spring-boot, java, jdbc, jpa]
---

# 4.8 Spring Boot and Oracle

!!! abstract "Chapter card"
    **Stage:** 4 · **Prerequisites:** 2.9, 2.11, 3.1 · **Time:** 5 hours ·
    **Stack:** Java 21, Spring Boot 3.x, Hibernate 6, Oracle JDBC, HikariCP, Flyway

!!! note "Not compiled here"
    The Java and configuration below were written for this playbook and not
    compiled or run. Spring Boot 4 has also been released; the concepts are
    unchanged, but check property names and dependency coordinates for the
    version you use.

## At a glance

| Subtopic | In one line |
|---|---|
| Driver and pool | Oracle JDBC, HikariCP, sizing |
| Access styles | JPA/Hibernate, Spring Data, `JdbcClient`, MyBatis |
| Entities and mappings | Identity keys, relationships, fetch strategy |
| Transactions | `@Transactional`, propagation, isolation |
| Locking | `@Version` and pessimistic locks |
| Stored procedures and native SQL | When and how |
| Migrations | Flyway |
| Error handling and observability | Translating ORA errors; metrics; tracing |
| What belongs where | Application layer versus database layer |

## 1. Dependencies and configuration

```xml
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
<dependency><groupId>com.oracle.database.jdbc</groupId><artifactId>ojdbc11</artifactId><scope>runtime</scope></dependency>
<dependency><groupId>org.flywaydb</groupId><artifactId>flyway-database-oracle</artifactId></dependency>
```

```yaml
spring:
  datasource:
    url: jdbc:oracle:thin:@//fm-db.example.internal:1521/fm_oltp     # a service, not a SID
    username: ${DB_USER}
    password: ${DB_PASSWORD}                                        # from a secret store
    hikari:
      maximum-pool-size: 10
      minimum-idle: 10                 # fixed-size pool
      connection-timeout: 3000         # fail fast when the pool is exhausted
      max-lifetime: 1800000
      keepalive-time: 300000
      data-source-properties:
        oracle.jdbc.implicitStatementCacheSize: 50
        oracle.net.CONNECT_TIMEOUT: 5000
        oracle.jdbc.ReadTimeout: 30000
        oracle.jdbc.defaultRowPrefetch: 100
        v$session.program: freshmart-order-service
  jpa:
    open-in-view: false
    hibernate.ddl-auto: validate       # Flyway owns the schema
    properties:
      hibernate.jdbc.batch_size: 50
      hibernate.order_inserts: true
      hibernate.order_updates: true
      hibernate.jdbc.fetch_size: 100
  flyway:
    enabled: true
    locations: classpath:db/migration
```

### Pool sizing

A database server can run about as many sessions concurrently as it has CPU
cores. A pool larger than that only moves the queue from the application (where
it is visible and cheap) into the database (where it causes contention).

- Start with **total** connections across all application instances at roughly 1 to 2 × database CPU cores, then measure.
- 20 pods × `maximum-pool-size: 50` = 1,000 sessions is a design error, not a safety margin.
- Fixed size (`minimum-idle = maximum-pool-size`) avoids connection storms.
- Short `connection-timeout`: fail fast and shed load.
- For RAC/Data Guard resilience use **UCP** (FAN, Application Continuity) instead of HikariCP, or accept reconnect-and-retry.

## 2. Access styles

| Style | Strength | Weakness | Use for |
|---|---|---|---|
| **Spring Data JPA / Hibernate** | Productivity, mapping, caching, dirty checking | Hidden SQL, N+1 queries, awkward for sets | CRUD on aggregates |
| **`JdbcClient` / `JdbcTemplate`** | Exact SQL, full Oracle features | Manual mapping | Reports, analytic SQL, bulk DML |
| **MyBatis** | SQL in mapper files with result mapping | Another framework | SQL-first teams |
| **jOOQ** | Type-safe SQL DSL | Commercial licence for Oracle | SQL-first with compile-time checks |
| **Stored procedures** | One round trip, set-based, shared by all clients | Deployment and testing discipline | Multi-statement transactions on hot paths |

Mixing is normal: JPA for writes of single aggregates, native SQL for reads
that span them.

## 3. Entities

```java
@Entity
@Table(name = "CUSTOMERS")
public class Customer {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)      // identity column
    @Column(name = "CUSTOMER_ID")
    private Long id;

    @Column(name = "CUSTOMER_NAME", nullable = false, length = 150)
    private String name;

    @Column(nullable = false, unique = true)
    private String email;

    private String phone;

    @Column(nullable = false)
    private String city;

    @Version                                                 // optimistic locking
    @Column(name = "ROW_VERSION")
    private Long version;

    @OneToMany(mappedBy = "customer", fetch = FetchType.LAZY)
    private List<Order> orders = new ArrayList<>();
    // getters and setters
}

@Entity
@Table(name = "ORDERS")
public class Order {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "ORDER_ID")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "CUSTOMER_ID")
    private Customer customer;

    @Enumerated(EnumType.STRING)
    private OrderStatus status;

    @Column(name = "TOTAL_AMOUNT", precision = 12, scale = 2)
    private BigDecimal totalAmount;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();
}
```

| Mapping decision | Guidance |
|---|---|
| Key generation | `IDENTITY` is simple but **disables JDBC insert batching** in Hibernate. For high insert volume use `SEQUENCE` with `allocationSize` equal to the sequence's `INCREMENT BY` (pooled optimizer) |
| Money | `BigDecimal`, never `double` |
| Dates | `LocalDate` ↔ `DATE` (date only), `LocalDateTime` ↔ `TIMESTAMP`, `OffsetDateTime` ↔ `TIMESTAMP WITH TIME ZONE` |
| Associations | `LAZY` everywhere; fetch explicitly per use case |
| Enums | `EnumType.STRING` to match the check constraints |
| Composite keys | `@EmbeddedId` for `order_items (order_id, line_no)` |
| Virtual columns (`line_total`) | `@Column(insertable = false, updatable = false)` |
| Trigger-maintained `row_version` | The FreshMart trigger also increments the column: with `@Version` choose **one** mechanism (remove the trigger increment or map the column as generated) |

### The N+1 problem

```java
List<Order> orders = orderRepository.findByStatus(OrderStatus.PLACED);   // 1 query
orders.forEach(o -> o.getCustomer().getName());                          // + 1 query per order
```

Fixes: a fetch join or entity graph, a DTO projection, or batch fetching
(`hibernate.default_batch_fetch_size`).

```java
public interface OrderRepository extends JpaRepository<Order, Long> {

    @Query("select o from Order o join fetch o.customer where o.status = :status")
    List<Order> findWithCustomerByStatus(@Param("status") OrderStatus status);

    @Query(value = """
            SELECT o.order_id AS orderId, o.order_date AS orderDate, o.status, o.total_amount AS totalAmount
            FROM   orders o
            WHERE  o.customer_id = :customerId
            ORDER  BY o.order_date DESC
            FETCH  FIRST :limit ROWS ONLY
            """, nativeQuery = true)
    List<OrderSummary> findRecent(@Param("customerId") long customerId, @Param("limit") int limit);
}
```

Turn on SQL logging in development and count the statements per request. That
one habit prevents most ORM performance problems.

## 4. Transactions

```java
@Service
public class CheckoutService {

    private final JdbcClient jdbc;

    @Transactional(timeout = 10)                       // one database transaction
    public long placeOrder(long cartId, long addressId, long warehouseId, String couponCode) {
        var call = new SimpleJdbcCall(jdbcTemplate)
                .withCatalogName("ORDER_PKG").withProcedureName("PLACE_ORDER");
        Map<String, Object> out = call.execute(Map.of(
                "P_CART_ID", cartId, "P_ADDRESS_ID", addressId,
                "P_WAREHOUSE_ID", warehouseId, "P_COUPON_CODE", couponCode));
        return ((Number) out.get("P_ORDER_ID")).longValue();
    }
}
```

*(A `null` coupon needs a `MapSqlParameterSource`, since `Map.of` rejects nulls.)*

| Rule | Why |
|---|---|
| `@Transactional` on the **service** method that is the business operation | One unit of work, one commit |
| No remote calls (payment gateway, email, Kafka) inside the transaction | They hold locks and a pooled connection while waiting ([incident 3](../performance-incidents/01-incidents.md)) |
| `readOnly = true` for queries | Skips dirty checking; lets the framework route to replicas |
| Rollback happens on unchecked exceptions by default | Declare `rollbackFor` for checked ones |
| Self-invocation bypasses the proxy | A `@Transactional` method called from the same class is not transactional |
| `REQUIRES_NEW` uses a **second connection** | Can exhaust the pool and deadlock on itself |
| Keep the default isolation (`READ COMMITTED`) | Use `SERIALIZABLE` only with retry logic for `ORA-08177` |
| Avoid XA/JTA across services | Use the outbox pattern ([4.3](../distributed-databases/01-distributed.md)) |

## 5. Locking

```java
// Optimistic: @Version adds "AND row_version = ?" to the UPDATE.
// A concurrent change throws ObjectOptimisticLockingFailureException: reload and retry or report.

// Pessimistic: SELECT ... FOR UPDATE
@Lock(LockModeType.PESSIMISTIC_WRITE)
@QueryHints(@QueryHint(name = "jakarta.persistence.lock.timeout", value = "3000"))   // WAIT 3
@Query("select i from Inventory i where i.id = :id")
Optional<Inventory> findForUpdate(@Param("id") InventoryId id);
```

For stock reservation prefer the single conditional update:

```java
int updated = jdbc.sql("""
        UPDATE inventory SET qty_reserved = qty_reserved + :qty
        WHERE  warehouse_id = :wh AND product_id = :pid
        AND    qty_on_hand - qty_reserved >= :qty
        """).param("qty", qty).param("wh", warehouseId).param("pid", productId).update();
if (updated == 0) throw new InsufficientStockException(productId);
```

## 6. Migrations with Flyway

```text
src/main/resources/db/migration/
  V1__create_schema.sql            (sql/schema/01_tables.sql)
  V2__order_pkg.sql
  V3__add_delivery_slots.sql
  R__views.sql                     (repeatable: re-applied when its checksum changes)
```

- Versioned migrations are immutable once released; fix forward with a new one.
- Oracle DDL auto-commits: a failed migration is **not** rolled back. Keep each migration small and re-runnable (`IF NOT EXISTS` on 23ai+).
- Run migrations from the **pipeline** with the schema owner's credentials, not at application start in production; the runtime user must not have DDL rights.
- Make changes backward compatible (expand, migrate, contract) so old and new application versions can run together ([4.9](../database-devops/01-devops.md)).
- Liquibase is the alternative (changelogs, rollback blocks, SQLcl integration).

## 7. Error handling

| Oracle error | Spring exception | Response |
|---|---|---|
| `ORA-00001` unique violation | `DuplicateKeyException` | 409 Conflict, or treat as idempotent success |
| `ORA-02291` / `ORA-02292` foreign key | `DataIntegrityViolationException` | 422 / 409 |
| `ORA-00060` deadlock | `CannotAcquireLockException` (deadlock loser) | Retry the whole transaction |
| `ORA-08177` serialization | `CannotSerializeTransactionException` | Retry |
| `ORA-30006` / `ORA-00054` lock timeout | `CannotAcquireLockException` | Retry or 409 |
| `ORA-20001` .. `-20999` application errors | `UncategorizedSQLException` | Map by error code to domain exceptions |
| Pool exhausted | `CannotGetJdbcConnectionException` | 503; shed load |

```java
@ExceptionHandler(UncategorizedSQLException.class)
ResponseEntity<Problem> handle(UncategorizedSQLException e) {
    return switch (e.getSQLException().getErrorCode()) {
        case 20002 -> problem(HttpStatus.CONFLICT, "INSUFFICIENT_STOCK");
        case 20003 -> problem(HttpStatus.UNPROCESSABLE_ENTITY, "INVALID_COUPON");
        default    -> throw e;
    };
}
```

Retry only **whole transactions**, only for transient errors, with backoff and
a limit, and only when the operation is idempotent.

## 8. Observability

- Micrometer exposes HikariCP metrics: `hikaricp.connections.active`, `.pending`, `.acquire`, `.usage`. **Pending > 0** for long is the alarm.
- Set module/action/client id so the DBA can attribute SQL to endpoints (Oracle JDBC end-to-end metrics, or `DBMS_APPLICATION_INFO` on borrow).
- Slow-query logging and statement counts per request (datasource-proxy, Hibernate statistics).
- Tracing: OpenTelemetry JDBC instrumentation; Oracle JDBC provides an OpenTelemetry provider in recent drivers.
- Health indicator with a short validation timeout.

## 9. What belongs where

| Concern | Database | Application |
|---|---|---|
| Keys, uniqueness, referential integrity, value ranges | **Constraints** | Also validate for user experience |
| Multi-statement atomic business transaction on hot data | Stored procedure **or** one short `@Transactional` method | Orchestration |
| Set-based processing of many rows | SQL / PL/SQL | Not row-by-row loops over the network |
| Calls to external systems, workflows, retries | | **Application** |
| Presentation, formatting, authorization of user actions | Row-level security where required | **Application** |
| Reporting queries | SQL, views, MVs | Thin mapping |
| Schema changes | Migrations via pipeline | Never at run time |

## 10. Common mistakes

- Oversized pools; pool per pod multiplied by autoscaling.
- `open-in-view: true` (default): lazy loading during view rendering holds a connection for the whole request.
- N+1 queries.
- `ddl-auto: update` in production.
- Remote calls inside transactions.
- Concatenated SQL in `@Query` or `JdbcTemplate`.
- Default fetch size of 10 for large exports.
- Catching exceptions and continuing in a transaction already marked rollback-only.

## FreshMart example

=== "Scenario"

    Implement "customer updates their phone number" safely against concurrent
    edits by a support agent, with a clear answer to the client.

=== "Java"

    ```java
    @Service
    public class CustomerService {
        private final CustomerRepository customers;

        @Transactional
        public CustomerDto updatePhone(long id, String phone, long expectedVersion) {
            Customer c = customers.findById(id).orElseThrow(() -> new NotFoundException(id));
            if (c.getVersion() != expectedVersion) {
                throw new StaleDataException(id);            // fast path: client had old data
            }
            c.setPhone(phone);                               // flushed at commit:
            return CustomerDto.from(c);                      // UPDATE ... WHERE customer_id=? AND row_version=?
        }
    }

    @RestControllerAdvice
    class Errors {
        @ExceptionHandler({StaleDataException.class, ObjectOptimisticLockingFailureException.class})
        ResponseEntity<Problem> conflict() {
            return ResponseEntity.status(HttpStatus.CONFLICT)
                    .body(new Problem("CUSTOMER_CHANGED", "Reload and try again"));
        }
    }
    ```

=== "Behavior"

    | Time | Customer app | Support agent | Result |
    |---|---|---|---|
    | t0 | Reads customer 101, version 4 | Reads customer 101, version 4 | |
    | t1 | | Updates city, commits | version 5 |
    | t2 | Sends phone with version 4 | | 409 CUSTOMER_CHANGED |
    | t3 | Reloads (version 5), resends | | 200, version 6 |

    Illustrative sequence. The version check in the `UPDATE` covers the race
    that the in-memory check cannot.

=== "Takeaway"

    No lock was held across the user's think time, and neither change was
    lost. The API contract carries the version (or an ETag) so the client
    takes part in concurrency control.

## Check yourself

??? question "Interview questions"
    1. **(Intermediate)** How do you size a connection pool?
    2. **(Intermediate)** What is the N+1 problem and how do you fix it?
    3. **(Senior)** Why does `GenerationType.IDENTITY` hurt batch inserts in Hibernate?
    4. **(Senior)** What goes wrong with a remote call inside `@Transactional`?
    5. **(Architect)** Stored procedures or ORM for an order platform? *Both, by workload: ORM for aggregate CRUD and developer velocity; SQL/PLSQL APIs for hot multi-row transactions, set processing and anything shared across clients. Fix the rule in an ADR and enforce it by review.*

??? example "Exercises"
    1. Map `OrderItem` with an `@EmbeddedId`.
    2. Write a repository method returning the top 5 products by revenue as a DTO projection with native SQL.
    3. Configure Hikari for 8 pods against a 16-core database and justify the numbers.

## Related

Next: [4.9 Database DevOps](../database-devops/01-devops.md).
