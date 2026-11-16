---
tags: [stage-4, oracle-26ai, vector-search, json, graph]
---

# 4.7 Oracle AI Database 26ai capabilities

!!! abstract "Chapter card"
    **Stage:** 4 · **Prerequisites:** 2.6, 2.12 · **Time:** 5 hours ·
    **Applies to:** 23ai and 26ai unless a row says otherwise

!!! warning "Verification status"
    The syntax in this chapter follows Oracle's 23ai/26ai documentation as the
    author understands it and was **not executed**. 26ai features arrive in
    release updates, and some are limited to specific platforms or to
    Autonomous Database. Confirm each feature in the *New Features Guide* and
    the *AI Vector Search User's Guide* for your exact release update before
    you design around it.

## At a glance

| Capability | What it adds | Core relational need? |
|---|---|---|
| AI Vector Search | `VECTOR` type, similarity search, vector indexes | Extension: semantic search, RAG |
| JSON Relational Duality | Tables exposed as updatable JSON documents | Extension that suits most API-driven apps |
| JSON Schema validation | Enforce document structure | Yes, wherever JSON is stored |
| SQL Property Graphs | Graph pattern queries (`GRAPH_TABLE`) over tables | Extension: relationship-heavy questions |
| JavaScript in the database (MLE) | Stored procedures in JavaScript | Optional |
| Select AI | Natural language to SQL through an LLM | Optional; platform-dependent |
| In-database machine learning | Train and score models with SQL | Optional |
| SQL and developer features | BOOLEAN, domains, annotations, `IF EXISTS`, and more | Yes: everyday use |
| Operational features | SQL Firewall, True Cache, lock-free reservations, Raft-replicated shards, automatic tuning | Depends on the system |

**The name:** 23ai was renamed from 23c in 2024. Oracle AI Database 26ai
replaced it in October 2025 as a release update of the same code line
(23.26.x). See [versions](../getting-started/versions.md).

## 1. AI Vector Search

### Concepts

An **embedding** is a list of numbers (a **vector**) produced by a machine
learning model so that items with similar *meaning* have vectors that are close
together. "Chapati flour" and "wheat atta" share no keywords but have nearby
embeddings. **Similarity search** finds the nearest vectors to a query vector.

| Term | Meaning |
|---|---|
| **Dense vector** | Every dimension has a value (typical sentence embeddings: 384 to 3072 dimensions) |
| **Sparse vector** | Mostly zeros; only non-zero positions are stored (keyword-style models such as SPLADE) |
| **Binary vector** | One bit per dimension: very compact, fast, less precise |
| **Distance metric** | `COSINE`, `EUCLIDEAN` (L2), `DOT`, `MANHATTAN`, `HAMMING` (binary), `JACCARD` |
| **Exact search** | Compare with every row: perfect recall, cost grows with table size |
| **Approximate search** | Use a vector index: far faster, recall below 100% |
| **RAG** | Retrieval-augmented generation: fetch relevant rows by similarity and give them to an LLM as context |

### The VECTOR data type

```sql
CREATE TABLE product_embeddings (
    product_id NUMBER(10) PRIMARY KEY REFERENCES products (product_id),
    embedding  VECTOR(384, FLOAT32)          -- dimensions, element format
);
-- Formats: INT8, FLOAT32, FLOAT64, BINARY. Sparse: VECTOR(30000, FLOAT32, SPARSE).
-- VECTOR without arguments accepts any shape (not recommended for indexed columns).
```

### Creating embeddings

Either in the application (call a model, insert the vector), or inside the
database with an ONNX model:

```sql
-- Load an ONNX embedding model once (file in a directory object)
BEGIN
    DBMS_VECTOR.LOAD_ONNX_MODEL('MODEL_DIR', 'all_MiniLM_L12_v2.onnx', 'DOC_MODEL');
END;
/
INSERT INTO product_embeddings (product_id, embedding)
SELECT product_id, VECTOR_EMBEDDING(doc_model USING product_name AS data)
FROM   products;
```

### Similarity search

```sql
SELECT p.product_name,
       VECTOR_DISTANCE(e.embedding, VECTOR_EMBEDDING(doc_model USING :search_text AS data), COSINE) AS distance
FROM   product_embeddings e
JOIN   products p ON p.product_id = e.product_id
WHERE  p.is_active = 'Y'                                  -- ordinary relational filter
ORDER  BY distance
FETCH  APPROX FIRST 5 ROWS ONLY;                          -- APPROX: allow the vector index
```

The strength of doing this **in the relational database** is that one statement
combines similarity with business predicates, joins, security policies and
transactions, with no second system to keep in sync.

### Vector indexes

| | HNSW (In-Memory Neighbor Graph) | IVF (Neighbor Partitions) |
|---|---|---|
| Structure | Layered graph of neighbors, held in memory | Vectors clustered around centroids, stored on disk |
| Speed and recall | Fastest, highest recall | Slower, tunable |
| Memory | Needs the **vector pool** (`VECTOR_MEMORY_SIZE`) sized for the whole index | Buffer cache |
| DML | Handled, with periodic refresh considerations | Handled; centroids drift over time |
| Choose when | The index fits in memory | Very large data sets |

```sql
CREATE VECTOR INDEX ix_prod_emb_hnsw ON product_embeddings (embedding)
    ORGANIZATION INMEMORY NEIGHBOR GRAPH
    DISTANCE COSINE WITH TARGET ACCURACY 95;

CREATE VECTOR INDEX ix_prod_emb_ivf ON product_embeddings (embedding)
    ORGANIZATION NEIGHBOR PARTITIONS
    DISTANCE COSINE WITH TARGET ACCURACY 90;
```

The index's distance metric must match the query's. `TARGET ACCURACY` trades
speed for recall and can be overridden per query. Measure recall on your own
data (`DBMS_VECTOR.INDEX_ACCURACY_QUERY`).

### Hybrid search

Keyword search finds exact terms (SKUs, brand names); vector search finds
meaning. A **hybrid vector index** combines an Oracle Text index and a vector
index on the same documents and fuses the scores (`DBMS_HYBRID_VECTOR.SEARCH`).
Most product search needs both.

### When vector search is appropriate

| Use it for | Do not use it for |
|---|---|
| Semantic product and document search | Exact lookups and filters (use B-tree indexes) |
| Recommendations by similarity | Transactions, totals, anything needing exact answers |
| RAG over your own data with row-level security | Replacing a well-designed relational model |
| Deduplication, anomaly detection | Data sets where keyword search already satisfies users |

Operational cost: embedding generation (CPU/GPU or API fees), memory for HNSW,
re-embedding everything when the model changes, and the need to evaluate
relevance with real queries.

## 2. JSON Relational Duality

Applications like documents; databases need normalized tables. A **duality
view** gives both: the data is stored relationally, and the view exposes it as
JSON documents that can be read **and written**.

```sql
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW order_dv AS
SELECT JSON {
    '_id'      : o.order_id,
    'status'   : o.status,
    'total'    : o.total_amount,
    'customer' : (SELECT JSON {'customerId' : c.customer_id, 'name' : c.customer_name}
                  FROM   customers c WITH NOINSERT NOUPDATE NODELETE
                  WHERE  c.customer_id = o.customer_id),
    'items'    : [SELECT JSON {'lineNo'   : oi.line_no,
                               'productId': oi.product_id,
                               'quantity' : oi.quantity,
                               'unitPrice': oi.unit_price}
                  FROM   order_items oi WITH INSERT UPDATE DELETE
                  WHERE  oi.order_id = o.order_id]
}
FROM orders o WITH INSERT UPDATE DELETE;

SELECT data FROM order_dv WHERE JSON_VALUE(data, '$._id') = 1002;
```

- Writing a document updates the underlying rows in one transaction; constraints still apply.
- Each document carries an **etag**; an update with a stale etag is rejected. That is lock-free optimistic concurrency for free.
- The same data stays available to SQL, reports and other duality views with different shapes.
- Access through SQL, REST (ORDS) or the MongoDB-compatible API.

Use it for API-shaped access to normalized data. It does not remove the need to
design the tables well.

## 3. JSON Schema validation

```sql
CREATE TABLE product_attributes (
    product_id NUMBER(10) PRIMARY KEY,
    attrs      JSON VALIDATE '{
        "type": "object",
        "properties": {
            "brand":   {"type": "string", "maxLength": 50},
            "organic": {"type": "boolean"},
            "tags":    {"type": "array", "items": {"type": "string"}}
        },
        "required": ["brand"],
        "additionalProperties": true
    }'
);
```

A document that breaks the schema is rejected like any other constraint
violation. `DBMS_JSON_SCHEMA.DESCRIBE` generates the JSON schema of a table or
duality view for client code generation.

## 4. SQL Property Graphs

A property graph models data as **vertices** and **edges**. In 23ai+ a graph is
a metadata object over existing tables (no data copy), queried with the
standard SQL/PGQ `GRAPH_TABLE` operator.

```sql
CREATE PROPERTY GRAPH freshmart_graph
    VERTEX TABLES (
        customers KEY (customer_id) LABEL customer PROPERTIES (customer_id, customer_name, city),
        products  KEY (product_id)  LABEL product  PROPERTIES (product_id, product_name)
    )
    EDGE TABLES (
        reviews KEY (review_id)
            SOURCE      KEY (customer_id) REFERENCES customers (customer_id)
            DESTINATION KEY (product_id)  REFERENCES products  (product_id)
            LABEL reviewed PROPERTIES (rating)
    );

-- Products liked (rating >= 4) by customers who liked the same product as Rahul
SELECT DISTINCT other_product
FROM   GRAPH_TABLE (freshmart_graph
         MATCH (me IS customer) -[r1 IS reviewed]-> (p IS product)
               <-[r2 IS reviewed]- (peer IS customer) -[r3 IS reviewed]-> (rec IS product)
         WHERE me.customer_id = 101 AND r1.rating >= 4 AND r2.rating >= 4 AND r3.rating >= 4
               AND rec.product_id <> p.product_id
         COLUMNS (rec.product_name AS other_product));
```

On the sample data: Rahul rated Apple 5 and Milk 4. Priya also rated Apple
(4) and rated Basmati Rice 5, so the query returns **Basmati Rice 5kg**
(derived by hand, not executed).

Graph queries express multi-hop paths that become unreadable as self-joins
(fraud rings, bill of materials, recommendations). For two or three fixed hops
on modest data, joins are fine.

## 5. JavaScript in the database (Multilingual Engine)

```sql
CREATE OR REPLACE MLE MODULE price_utils LANGUAGE JAVASCRIPT AS
export function withTax(price, ratePct) {
    return Math.round(price * (1 + ratePct / 100) * 100) / 100;
}
/
CREATE OR REPLACE FUNCTION price_with_tax (p_price NUMBER, p_rate NUMBER) RETURN NUMBER
    AS MLE MODULE price_utils SIGNATURE 'withTax(number, number)';
/
SELECT product_name, price_with_tax(unit_price, 5) FROM products WHERE product_id = 5;   -- 71.4
```

Server-side JavaScript lets teams reuse validation libraries and skills. It is
platform-limited (check supported platforms) and does not replace PL/SQL for
data-intensive logic: SQL calls from JavaScript still cross engines.

## 6. Select AI and LLM integration

**Select AI** translates natural language into SQL by sending schema metadata
(not data, unless you enable it) to a configured LLM:

```sql
BEGIN
    DBMS_CLOUD_AI.CREATE_PROFILE(
        profile_name => 'FM_AI',
        attributes   => '{"provider": "oci", "credential_name": "AI_CRED",
                          "object_list": [{"owner": "FRESHMART", "name": "ORDERS"},
                                          {"owner": "FRESHMART", "name": "CUSTOMERS"}]}');
END;
/
EXEC DBMS_CLOUD_AI.SET_PROFILE('FM_AI');
SELECT AI showsql how many orders were delivered in March 2025;
```

Originally an Autonomous Database feature; check availability for your
deployment. Treat generated SQL as **untrusted**: run it with a read-only,
least-privilege account behind views, review `showsql` output, add comments and
annotations so the model understands the schema, and never expose it directly
to end users without guardrails. Related: `DBMS_VECTOR_CHAIN` for chunking and
RAG pipelines, and AI agent frameworks announced with 26ai.

## 7. In-database machine learning

**Oracle Machine Learning (OML)** trains and applies models where the data is:
classification, regression, clustering, anomaly detection, time series, with
SQL (`DBMS_DATA_MINING`, `PREDICTION()`), Python and R interfaces, and AutoML.
ONNX models can be imported and scored in SQL. Benefits: no data extraction,
scoring in a query, database security. Limits: fewer algorithms than
specialized frameworks, and training load competes with the database.

## 8. SQL and developer features

Covered where they belong; summarized here.

| Feature | Chapter |
|---|---|
| `BOOLEAN`, `IF [NOT] EXISTS`, domains, annotations | [1.7](../sql-fundamentals/03-ddl.md) |
| `SELECT` without `FROM`, table value constructor, DML joins, `GROUP BY` alias, `RETURNING OLD/NEW` | [2.6](../advanced-sql/06-merge-topn-json.md) |
| Assertions, `QUALIFY`, later SQL additions (26ai RUs) | [1.9](../sql-fundamentals/05-constraints.md), [2.5](../advanced-sql/05-window-functions.md) |
| Schema privileges, `DB_DEVELOPER_ROLE`, SQL Firewall, TLS 1.3 | [3.5](../security/01-security.md) |
| Up to 4096 columns per table (`MAX_COLUMNS = EXTENDED`) | |
| Transactional Event Queues with Kafka-compatible APIs | [4.3](../distributed-databases/01-distributed.md) |

## 9. Operational features

| Feature | Benefit |
|---|---|
| **Lock-free reservations** | Concurrent updates of hot numeric columns without blocking ([2.11](../transactions/01-transactions-concurrency.md)) |
| **Priority transactions** | Low-priority transactions holding row locks are rolled back automatically when higher-priority ones wait |
| **True Cache** | Consistent, automatically maintained read cache ([4.4](../performance-engineering/04-scalability-features.md)) |
| **Raft replication** for the Globally Distributed Database | Consensus-based shard replicas with fast automatic failover |
| **Real-time SQL Plan Management**, automatic indexing, automatic materialized views, automatic transaction rollback | "AI-powered operations": self-tuning that reacts to regressions (several are limited to Exadata and Autonomous) |
| Bigfile defaults, tablespace shrink, unrestricted direct loads | Simpler storage operations |

## 10. Adoption guidance

1. **Get to the long-term release first.** The largest benefit of 26ai for most estates is the support horizon and the everyday SQL features, not AI.
2. **Core versus extension.** Vector search, graph, duality and JavaScript are *additions* to a sound relational design. Adopt each for a named use case with a measurable outcome.
3. **Prefer converged over separate** when the data already lives in Oracle: one security model, one backup, one transaction. Prefer a specialized system only when a requirement exceeds what the converged feature does.
4. **Check availability three ways:** release update, platform, edition/licence.
5. **Plan for model lifecycle** if you store embeddings: versioning, re-embedding, evaluation.
6. **Mind compatibility:** new data types and syntax cannot be replicated to or exported into 19c. Hold them back until fallback paths are retired.

## FreshMart example

=== "Scenario"

    Customers type "something for breakfast" into search and get nothing,
    because no product name contains "breakfast". FreshMart adds semantic
    search while keeping stock and price filters exact.

=== "SQL"

    ```sql
    ALTER TABLE products ADD (name_embedding VECTOR(384, FLOAT32));

    UPDATE products
    SET    name_embedding = VECTOR_EMBEDDING(doc_model USING product_name AS data);

    CREATE VECTOR INDEX ix_products_emb ON products (name_embedding)
        ORGANIZATION INMEMORY NEIGHBOR GRAPH DISTANCE COSINE WITH TARGET ACCURACY 95;

    SELECT p.product_name, p.unit_price, i.qty_on_hand - i.qty_reserved AS available
    FROM   products p
    JOIN   inventory i ON i.product_id = p.product_id AND i.warehouse_id = :wh
    WHERE  p.is_active = 'Y'
    AND    i.qty_on_hand - i.qty_reserved > 0
    AND    p.unit_price <= :max_price
    ORDER  BY VECTOR_DISTANCE(p.name_embedding,
                              VECTOR_EMBEDDING(doc_model USING :q AS data), COSINE)
    FETCH  APPROX FIRST 5 ROWS ONLY;
    ```

=== "Expected behavior"

    For `:q = 'something for breakfast'`, `:wh = 1`, `:max_price = 200`, a
    reasonable embedding model would rank items such as Whole Wheat Bread,
    Eggs, Full Cream Milk, Orange Juice and Assam Tea near the top.

    **Illustrative only.** The ranking depends entirely on the embedding
    model; nothing here was executed. What is certain is the relational part:
    only active products in stock in warehouse 1 priced at 200 or less can
    appear.

=== "Takeaway"

    Product names alone are thin text: real relevance comes from embedding
    richer descriptions, and from combining with keyword search (hybrid) so
    that "FRU-APL-001" still finds the apple. Start with an offline relevance
    test on 100 real queries before building anything else.

## Check yourself

??? question "Interview questions"
    1. **(Senior)** What is a vector embedding and how does similarity search differ from a `LIKE` search?
    2. **(Senior)** HNSW versus IVF indexes?
    3. **(Principal)** What problem does JSON Relational Duality solve that a JSON column does not?
    4. **(Principal)** When would you use a property graph instead of joins?
    5. **(Architect)** A team wants a separate vector database for RAG over customer documents stored in Oracle. Your evaluation? *Compare on consistency (one transaction and security model versus synchronization), filtering with relational predicates, scale and latency requirements, operational cost, and team skills. In-database vectors usually win when the source data and access rules are already in Oracle; a specialized store may win for very large, standalone corpora.*

??? example "Exercises"
    1. In a 23ai/26ai Free database, create a `VECTOR(3, FLOAT32)` column, insert three vectors by hand and order by `VECTOR_DISTANCE`.
    2. Create the `order_dv` duality view, read order 1002 as JSON, and update its status through the view.
    3. Create the property graph and find customers who reviewed the same product.

## Related

Next: [4.8 Spring Boot and Oracle](../spring-boot-integration/01-spring-boot.md).
References: [Oracle AI Vector Search and 26ai guides](../references/index.md).
