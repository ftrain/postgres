# PostgreSQL Glossary
## Comprehensive Terminology Reference

This glossary contains definitions of PostgreSQL-specific terms, database concepts, and technical jargon used throughout this encyclopedia. Terms are cross-referenced with related concepts and point to relevant sections of the documentation.

---

## A

**Access Method (AM)**
A pluggable interface for implementing index types or table storage. PostgreSQL provides B-tree, Hash, GiST, GIN, SP-GiST, BRIN, and Bloom access methods. Custom access methods can be implemented.
→ See: [Custom Access Methods](../08-extensions/access-methods.md)

**ACID**
The four properties guaranteeing reliable transaction processing:
- **Atomicity**: Transactions are all-or-nothing
- **Consistency**: Database remains in a valid state
- **Isolation**: Concurrent transactions don't interfere
- **Durability**: Committed changes persist
→ See: [Transaction Management](../05-transactions/acid-properties.md)

**Aggregate Function**
A function that computes a single result from multiple input rows (e.g., SUM, AVG, COUNT).
→ See: [Query Processing - Aggregation](../03-query-processing/aggregation.md)

**Analyzestat**
Statistics collector process that gathers information about database activity for the query planner.
→ See: [Process Architecture](../06-processes/statistics-collector.md)

**Autovacuum**
Background process that automatically performs VACUUM and ANALYZE operations to maintain database health.
→ See: [Maintenance - Autovacuum](../04-storage/vacuum.md#autovacuum)

---

## B

**Backend Process**
A server process dedicated to handling a single client connection.
→ See: [Process Architecture - Backends](../06-processes/backend-processes.md)

**Base Backup**
A complete copy of the database cluster taken while the database is running, used for point-in-time recovery or creating standbys.
→ See: [Utilities - pg_basebackup](../08-utilities/pg_basebackup.md)

**Berkeley DB**
Historical: UC Berkeley's database. PostgreSQL descended from Berkeley POSTGRES, unrelated to Berkeley DB.

**bgwriter (Background Writer)**
Process that writes dirty buffers from shared memory to disk, smoothing I/O load.
→ See: [Process Architecture - bgwriter](../06-processes/auxiliary-processes.md#bgwriter)

**Bitmap Index Scan**
An index scan method that builds a bitmap of matching tuples before accessing the heap, efficient for multiple conditions.
→ See: [Query Processing - Index Scans](../03-query-processing/index-scans.md)

**BKI (Backend Interface)**
The format used for bootstrap data files (e.g., postgres.bki) that create initial system catalogs.
→ See: [Build System - Bootstrap](../09-build-system/bootstrap.md)

**Block**
See **Page**

**Block Number**
Zero-based index of a page within a relation fork. Type: `BlockNumber` (32-bit unsigned).
→ See: [Storage - Page Layout](../04-storage/page-layout.md)

**BRIN (Block Range Index)**
Index type that stores summaries (min/max) for ranges of pages, very compact for correlated data.
→ See: [Indexes - BRIN](../04-storage/indexes.md#brin)

**Buffer**
An in-memory copy of a page from disk, managed by the buffer manager.
→ See: [Storage - Buffer Management](../04-storage/buffer-manager.md)

**Buffer Manager**
Subsystem that manages the buffer pool, implementing caching and replacement policies.
→ See: [Storage - Buffer Management](../04-storage/buffer-manager.md)

**Buffer Pool**
Collection of shared memory buffers for caching disk pages. Size controlled by `shared_buffers`.
→ See: [Configuration - Memory](../10-admin/configuration.md#shared_buffers)

**B-tree**
The default index type, implementing Lehman and Yao's high-concurrency B+ tree algorithm.
→ See: [Indexes - B-tree](../04-storage/indexes.md#btree)

---

## C

**Catalog**
System tables (pg_class, pg_attribute, etc.) that store metadata about database objects.
→ See: [Query Processing - Catalog System](../03-query-processing/catalog.md)

**Checkpointer**
Process that performs checkpoints, ensuring all dirty buffers are written and creating recovery points.
→ See: [Process Architecture - Checkpointer](../06-processes/auxiliary-processes.md#checkpointer)

**Checkpoint**
A point in the WAL sequence where all data file changes have been flushed to disk, enabling recovery.
→ See: [WAL - Checkpoints](../04-storage/wal.md#checkpoints)

**CID (Command ID)**
Identifier for a command within a transaction. Type: `CommandId` (32-bit unsigned).
→ See: [MVCC - Tuple Visibility](../05-transactions/mvcc.md#command-id)

**CLOG (Commit Log)**
Now called **pg_xact**. SLRU storing transaction commit status.
→ See: [Transactions - Commit Log](../05-transactions/commit-log.md)

**Clock-Sweep**
Buffer replacement algorithm that approximates LRU with low overhead.
→ See: [Storage - Buffer Replacement](../04-storage/buffer-manager.md#clock-sweep)

**Commitfest**
Month-long period focused on reviewing patches rather than developing new features.
→ See: [Development Process](../11-culture/commitfest.md)

**Connection Pooling**
Reusing database connections to reduce overhead. Typically done by external tools (pgBouncer, pgPool).
→ See: [Architecture - Connection Management](../06-processes/connection-pooling.md)

**Constraint**
Rule enforcing data integrity: PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, NOT NULL.
→ See: [DDL - Constraints](../02-sql/constraints.md)

**contrib**
Directory containing optional extensions and modules distributed with PostgreSQL.
→ See: [Extensions - Contrib Modules](../08-extensions/contrib.md)

**Cost Estimation**
Process of predicting resource usage for different query plans.
→ See: [Query Optimizer - Cost Model](../03-query-processing/cost-estimation.md)

**CTE (Common Table Expression)**
Named subquery defined with WITH clause. Can be recursive.
→ See: [SQL - CTEs](../02-sql/with-queries.md)

**ctid**
System column containing tuple's physical location (page number, tuple index).
→ See: [Storage - Tuple Format](../04-storage/tuple-format.md)

---

## D

**Data Directory (PGDATA)**
Directory containing all database files, configuration, and WAL.
→ See: [Installation - Data Directory](../10-admin/data-directory.md)

**Datum**
PostgreSQL's universal data container type. Can hold any PostgreSQL data value.
→ See: [Internals - Datum](../07-internals/datum.md)

**Deadlock**
Circular wait condition where transactions block each other. Detected and resolved automatically.
→ See: [Locking - Deadlock Detection](../05-transactions/deadlocks.md)

**Dirty Buffer**
A buffer containing modified data not yet written to disk.
→ See: [Storage - Buffer States](../04-storage/buffer-manager.md#buffer-states)

---

## E

**ECPG (Embedded SQL in C)**
Preprocessor allowing SQL to be embedded in C programs.
→ See: [Interfaces - ECPG](../07-interfaces/ecpg.md)

**Epoch**
32-bit counter incremented on XID wraparound. Combined with XID forms 64-bit FullTransactionId.
→ See: [Transactions - XID Wraparound](../05-transactions/wraparound.md)

**EState (Executor State)**
Per-query execution state passed between executor nodes.
→ See: [Executor - EState](../03-query-processing/executor.md#estate)

**Extension**
Packaged collection of SQL objects (types, functions, operators, etc.) managed as a unit.
→ See: [Extensions - Extension Mechanism](../08-extensions/extension-mechanism.md)

**ExprState (Expression State)**
Compiled representation of an expression for fast evaluation.
→ See: [Executor - Expression Evaluation](../03-query-processing/executor.md#expression-evaluation)

---

## F

**FDW (Foreign Data Wrapper)**
Interface for accessing external data sources as if they were PostgreSQL tables.
→ See: [Extensions - Foreign Data Wrappers](../08-extensions/fdw.md)

**Fill Factor**
Percentage of page to fill during index creation, leaving space for updates.
→ See: [Indexes - Fill Factor](../04-storage/indexes.md#fill-factor)

**fmgr (Function Manager)**
Subsystem managing function calls, including caching and calling conventions.
→ See: [Internals - Function Manager](../07-internals/fmgr.md)

**Fork**
Separate file storing different types of relation data: main, FSM, VM, init.
→ See: [Storage - Relation Forks](../04-storage/file-layout.md#forks)

**Freezing**
Setting old transaction IDs to FrozenTransactionId (2) to prevent wraparound.
→ See: [VACUUM - Freezing](../04-storage/vacuum.md#freezing)

**FSM (Free Space Map)**
Per-relation structure tracking available space in pages for efficient insertion.
→ See: [Storage - Free Space Map](../04-storage/fsm.md)

---

## G

**GEQO (Genetic Query Optimizer)**
Alternative query optimizer using genetic algorithm for queries with many tables.
→ See: [Optimizer - GEQO](../03-query-processing/geqo.md)

**GIN (Generalized Inverted Index)**
Index type for multi-valued data like arrays, JSONB, and full-text search.
→ See: [Indexes - GIN](../04-storage/indexes.md#gin)

**GiST (Generalized Search Tree)**
Extensible balanced tree structure for custom data types and operations.
→ See: [Indexes - GiST](../04-storage/indexes.md#gist)

**GUC (Grand Unified Configuration)**
PostgreSQL's configuration system, managing all server parameters.
→ See: [Configuration - GUC](../10-admin/configuration.md#guc-system)

---

## H

**Hash Join**
Join algorithm that builds hash table of one input and probes with the other.
→ See: [Joins - Hash Join](../03-query-processing/joins.md#hash-join)

**Heap**
Default table storage format, storing tuples in no particular order.
→ See: [Storage - Heap AM](../04-storage/heap.md)

**Heap-Only Tuple (HOT)**
Update optimization keeping new tuple version on same page without updating indexes.
→ See: [Storage - HOT Updates](../04-storage/hot.md)

**Hook**
Callback mechanism allowing extensions to intercept and modify PostgreSQL behavior.
→ See: [Extensions - Hooks](../08-extensions/hooks.md)

**Hot Standby**
Replica that accepts read-only queries while in continuous recovery.
→ See: [Replication - Hot Standby](../06-replication/hot-standby.md)

---

## I

**Index**
Data structure for efficiently finding rows matching conditions.
→ See: [Storage - Indexes](../04-storage/indexes.md)

**Index-Only Scan**
Optimization returning data from index without accessing heap, using visibility map.
→ See: [Indexes - Index-Only Scans](../04-storage/indexes.md#index-only-scans)

**Ingres**
Predecessor database system at UC Berkeley, led by Michael Stonebraker.
→ See: [History - Ingres](../00-introduction.md#ingres)

**initdb**
Utility that initializes a new database cluster.
→ See: [Utilities - initdb](../08-utilities/initdb.md)

**Item Pointer (ItemPointer)**
See **TID (Tuple Identifier)**

---

## J

**JIT (Just-In-Time Compilation)**
LLVM-based compilation of expressions and tuple deforming for faster execution.
→ See: [Executor - JIT](../03-query-processing/jit.md)

**Join**
Combining rows from multiple tables based on related columns.
→ See: [SQL - Joins](../02-sql/joins.md)

---

## K

**Key**
Column(s) uniquely identifying rows (primary key) or referencing other tables (foreign key).
→ See: [DDL - Keys](../02-sql/keys.md)

---

## L

**Large Object (LOB)**
Object stored outside normal tables, accessed via special API. Deprecated in favor of bytea/text.
→ See: [Data Types - Large Objects](../02-sql/large-objects.md)

**Latch**
Lightweight waiting mechanism for processes/threads to sleep until woken.
→ See: [IPC - Latches](../06-processes/latches.md)

**libpq**
Official PostgreSQL C client library.
→ See: [Interfaces - libpq](../07-interfaces/libpq.md)

**Listen/Notify**
Asynchronous notification mechanism for publishing messages between sessions.
→ See: [Features - LISTEN/NOTIFY](../02-sql/listen-notify.md)

**Lock**
Mechanism preventing conflicting concurrent access. Multiple granularities and modes.
→ See: [Concurrency - Locking](../05-transactions/locking.md)

**Lock Manager (lmgr)**
Subsystem managing heavyweight locks on database objects.
→ See: [Locking - Lock Manager](../05-transactions/lock-manager.md)

**Logical Decoding**
Extracting changes from WAL in readable format, foundation for logical replication.
→ See: [Replication - Logical Decoding](../06-replication/logical-decoding.md)

**Logical Replication**
Row-level replication using logical decoding, allowing selective table replication.
→ See: [Replication - Logical Replication](../06-replication/logical-replication.md)

**LSN (Log Sequence Number)**
64-bit position in WAL stream. Type: `XLogRecPtr`.
→ See: [WAL - LSN](../04-storage/wal.md#lsn)

**LWLock (Lightweight Lock)**
Spinlock with queue for waiting, used for internal data structures.
→ See: [Locking - LWLocks](../05-transactions/lwlocks.md)

---

## M

**Merge Join**
Join algorithm for sorted inputs, scanning both inputs simultaneously.
→ See: [Joins - Merge Join](../03-query-processing/joins.md#merge-join)

**MVCC (Multi-Version Concurrency Control)**
Concurrency control mechanism where readers see consistent snapshot without blocking writers.
→ See: [Transactions - MVCC](../05-transactions/mvcc.md)

---

## N

**Nested Loop Join**
Join algorithm evaluating inner relation once per outer row.
→ See: [Joins - Nested Loop](../03-query-processing/joins.md#nested-loop)

**Node**
Base type for parse trees, plan trees, and executor state trees.
→ See: [Internals - Node System](../07-internals/nodes.md)

---

## O

**OID (Object Identifier)**
Unique identifier for system catalog rows. Type: `Oid` (32-bit unsigned).
→ See: [Catalog - OIDs](../03-query-processing/catalog.md#oids)

**ORDBMS (Object-Relational Database Management System)**
Database combining relational model with object-oriented features.
→ See: [Introduction - What is PostgreSQL](../00-introduction.md)

---

## P

**Page**
Basic I/O unit, typically 8KB. Contains header, line pointers, tuples, and special space.
→ See: [Storage - Page Layout](../04-storage/page-layout.md)

**Parallel Query**
Query execution using multiple worker processes for faster results.
→ See: [Executor - Parallel Execution](../03-query-processing/parallel.md)

**Parse Tree**
Representation of SQL query after parsing but before planning.
→ See: [Query Processing - Parser](../03-query-processing/parser.md)

**Partition**
Dividing large table into smaller physical pieces while appearing as single table.
→ See: [DDL - Partitioning](../02-sql/partitioning.md)

**Path**
Possible execution strategy for (part of) a query, with estimated costs.
→ See: [Optimizer - Path Generation](../03-query-processing/paths.md)

**pg_dump**
Utility for logical database backup.
→ See: [Utilities - pg_dump](../08-utilities/pg_dump.md)

**PGDATA**
See **Data Directory**

**PGXS (PostgreSQL Extension Building Infrastructure)**
Build system for compiling extensions outside the source tree.
→ See: [Extensions - PGXS](../08-extensions/pgxs.md)

**PITR (Point-In-Time Recovery)**
Recovering database to specific moment using base backup and WAL archives.
→ See: [Backup - PITR](../10-admin/pitr.md)

**Plan**
Executable representation of query, produced by planner from cheapest path.
→ See: [Query Processing - Planner](../03-query-processing/planner.md)

**PlanState**
Runtime state for executing a plan node.
→ See: [Executor - Plan States](../03-query-processing/executor.md#plan-states)

**PL/pgSQL**
PostgreSQL's default procedural language, similar to PL/SQL.
→ See: [Procedural Languages - PL/pgSQL](../08-extensions/plpgsql.md)

**Postmaster**
Main server process that manages authentication and spawns backends.
→ See: [Process Architecture - Postmaster](../06-processes/postmaster.md)

**POSTGRES**
Original database system developed at UC Berkeley (1986-1994), PostgreSQL's ancestor.
→ See: [History - Berkeley POSTGRES](../00-introduction.md#postgres)

**Prepared Statement**
Pre-parsed query plan that can be executed multiple times with different parameters.
→ See: [SQL - Prepared Statements](../02-sql/prepared.md)

**Primary Key**
Column(s) uniquely identifying each row in a table.
→ See: [DDL - Primary Keys](../02-sql/constraints.md#primary-key)

**psql**
Interactive terminal for PostgreSQL.
→ See: [Utilities - psql](../08-utilities/psql.md)

---

## Q

**Query**
Parsed and analyzed representation of SQL statement.
→ See: [Query Processing - Query Structure](../03-query-processing/query-struct.md)

**Query Optimizer**
See **Planner**

**Query Rewrite**
Transformation of queries by rules, views, and row security policies.
→ See: [Query Processing - Rewriter](../03-query-processing/rewriter.md)

---

## R

**Range Table Entry (RTE)**
Describes one table/subquery/function in FROM clause.
→ See: [Query Processing - Range Tables](../03-query-processing/range-table.md)

**Relation**
Generic term for table, index, sequence, view, etc.
→ See: [Catalog - Relations](../03-query-processing/catalog.md#relations)

**Relfilenode**
File name for storing relation's data. May differ from OID after certain operations.
→ See: [Storage - File Layout](../04-storage/file-layout.md#relfilenode)

**Replication Slot**
Named persistent state for streaming or logical replication, preventing WAL deletion.
→ See: [Replication - Replication Slots](../06-replication/slots.md)

**Resource Manager (RM)**
Module handling specific WAL record types (heap, btree, xact, etc.).
→ See: [WAL - Resource Managers](../04-storage/wal.md#resource-managers)

**Row-Level Security (RLS)**
Per-row access control using policies.
→ See: [Security - Row-Level Security](../10-admin/rls.md)

---

## S

**Sequential Scan**
Reading all tuples in a relation sequentially.
→ See: [Access Methods - Sequential Scan](../04-storage/seqscan.md)

**Serializable Snapshot Isolation (SSI)**
Algorithm implementing true SERIALIZABLE isolation without locking.
→ See: [Isolation - SSI](../05-transactions/ssi.md)

**Shared Buffers**
Main buffer pool in shared memory for caching pages.
→ See: [Configuration - shared_buffers](../10-admin/configuration.md#shared_buffers)

**Shared Memory**
Memory segment accessible to all PostgreSQL processes.
→ See: [IPC - Shared Memory](../06-processes/shared-memory.md)

**Slotted Page**
Page layout with indirection layer (line pointers) between tuples and their references.
→ See: [Storage - Page Layout](../04-storage/page-layout.md)

**SLRU (Simple LRU)**
Mini buffer manager for small frequently-accessed data (commit log, subtransactions, etc.).
→ See: [Storage - SLRU](../04-storage/slru.md)

**Snapshot**
View of database state at a point in time, determining tuple visibility.
→ See: [MVCC - Snapshots](../05-transactions/snapshots.md)

**SP-GiST (Space-Partitioned GiST)**
Index for non-balanced tree structures like quad-trees and tries.
→ See: [Indexes - SP-GiST](../04-storage/indexes.md#spgist)

**SPI (Server Programming Interface)**
API for writing server-side functions that execute SQL.
→ See: [Extensions - SPI](../08-extensions/spi.md)

**Spinlock**
Low-level lock implemented with atomic CPU instructions.
→ See: [Locking - Spinlocks](../05-transactions/spinlocks.md)

**SQL (Structured Query Language)**
Standard language for relational databases.
→ See: [SQL Reference](../02-sql/README.md)

**SSI**
See **Serializable Snapshot Isolation**

**Standby**
Replica server receiving changes via streaming or WAL shipping.
→ See: [Replication - Standbys](../06-replication/standbys.md)

**Statistics**
Information about data distribution used by query planner.
→ See: [Optimizer - Statistics](../03-query-processing/statistics.md)

**Streaming Replication**
Real-time replication by streaming WAL records to standby.
→ See: [Replication - Streaming](../06-replication/streaming.md)

**syscache (System Cache)**
In-memory cache of frequently-accessed catalog tuples.
→ See: [Catalog - Syscache](../03-query-processing/syscache.md)

---

## T

**Tablespace**
Named location on filesystem where database objects can be stored.
→ See: [Storage - Tablespaces](../04-storage/tablespaces.md)

**TID (Tuple Identifier)**
Physical location of tuple: (block number, offset). Type: `ItemPointerData`.
→ See: [Storage - TIDs](../04-storage/tid.md)

**Timeline**
Branch in WAL history after recovery to a point in time.
→ See: [Recovery - Timelines](../06-replication/timelines.md)

**TOAST (The Oversized-Attribute Storage Technique)**
Mechanism for storing large values out-of-line from main table.
→ See: [Storage - TOAST](../04-storage/toast.md)

**Transaction**
Atomic unit of work, either fully completed or fully rolled back.
→ See: [Transactions - Basics](../05-transactions/basics.md)

**Transaction ID (XID)**
Unique identifier for each transaction. Type: `TransactionId` (32-bit), wraps around.
→ See: [Transactions - Transaction IDs](../05-transactions/xid.md)

**Trigger**
Function automatically executed when specified event occurs on a table.
→ See: [Triggers - Overview](../02-sql/triggers.md)

**Tuple**
Single row in a table or index.
→ See: [Storage - Tuple Format](../04-storage/tuple-format.md)

**Two-Phase Commit (2PC)**
Protocol for coordinating distributed transactions across multiple databases.
→ See: [Transactions - Two-Phase Commit](../05-transactions/2pc.md)

---

## U

**Unlogged Table**
Table whose changes aren't written to WAL, faster but not crash-safe.
→ See: [DDL - Unlogged Tables](../02-sql/unlogged.md)

---

## V

**VACUUM**
Process that removes dead tuples, updates statistics, and prevents XID wraparound.
→ See: [Maintenance - VACUUM](../04-storage/vacuum.md)

**Visibility Map (VM)**
Bitmap tracking which pages have all tuples visible to all transactions.
→ See: [Storage - Visibility Map](../04-storage/vm.md)

---

## W

**WAL (Write-Ahead Log)**
Transaction log ensuring durability and enabling recovery. Also called "xlog" internally.
→ See: [Storage - WAL](../04-storage/wal.md)

**WAL Archiving**
Copying completed WAL segments to external storage for backup/recovery.
→ See: [Backup - WAL Archiving](../10-admin/wal-archiving.md)

**WAL Sender (walsender)**
Process streaming WAL to standby servers.
→ See: [Replication - WAL Sender](../06-replication/walsender.md)

**WAL Writer (walwriter)**
Process that periodically writes WAL buffers to disk.
→ See: [Process Architecture - walwriter](../06-processes/auxiliary-processes.md#walwriter)

**Window Function**
Function operating on set of rows related to current row (e.g., rank(), lag()).
→ See: [SQL - Window Functions](../02-sql/window-functions.md)

---

## X

**XID**
See **Transaction ID**

**xlog**
Internal name for WAL in source code and file structures.
→ See: [WAL - Overview](../04-storage/wal.md)

**xmin, xmax**
Transaction IDs in tuple header indicating creation and deletion transactions.
→ See: [MVCC - Tuple Visibility](../05-transactions/mvcc.md#xmin-xmax)

---

## Z

**Zero Page**
Newly allocated page filled with zeros, avoiding leaked data from previous use.
→ See: [Storage - Page Initialization](../04-storage/page-init.md)

---

## Acronyms Quick Reference

- **2PC**: Two-Phase Commit
- **ACL**: Access Control List
- **AM**: Access Method
- **API**: Application Programming Interface
- **BRIN**: Block Range Index
- **CID**: Command ID
- **CLOG**: Commit Log (now pg_xact)
- **CPU**: Central Processing Unit
- **CRC**: Cyclic Redundancy Check
- **CTE**: Common Table Expression
- **CTID**: Current Tuple ID
- **DDL**: Data Definition Language
- **DML**: Data Manipulation Language
- **ECPG**: Embedded C for PostgreSQL
- **FDW**: Foreign Data Wrapper
- **FSM**: Free Space Map
- **GEQO**: Genetic Query Optimizer
- **GIN**: Generalized Inverted Index
- **GiST**: Generalized Search Tree
- **GUC**: Grand Unified Configuration
- **HOT**: Heap-Only Tuple
- **I/O**: Input/Output
- **IPC**: Inter-Process Communication
- **JIT**: Just-In-Time (compilation)
- **LO**: Large Object
- **LOB**: Large Object
- **LSN**: Log Sequence Number
- **LWLock**: Lightweight Lock
- **MVCC**: Multi-Version Concurrency Control
- **OID**: Object Identifier
- **ORDBMS**: Object-Relational DBMS
- **PID**: Process ID
- **PITR**: Point-In-Time Recovery
- **PGDATA**: PostgreSQL Data Directory
- **PGXS**: PostgreSQL Extension Building Infrastructure
- **RM**: Resource Manager
- **RLS**: Row-Level Security
- **RTE**: Range Table Entry
- **SPI**: Server Programming Interface
- **SP-GiST**: Space-Partitioned GiST
- **SQL**: Structured Query Language
- **SRF**: Set-Returning Function
- **SSI**: Serializable Snapshot Isolation
- **TID**: Tuple Identifier
- **TOAST**: The Oversized-Attribute Storage Technique
- **TPS**: Transactions Per Second
- **VM**: Visibility Map
- **WAL**: Write-Ahead Log
- **XID**: Transaction ID
- **XLOG**: Transaction Log (internal name for WAL)

---

## See Also

- **[Index](index.md)**: Alphabetical index of all topics
- **[Introduction](../00-introduction.md)**: Overview of PostgreSQL
- **[Architecture Overview](../01-architecture/overview.md)**: High-level system architecture

---

*This glossary is continuously updated as PostgreSQL evolves. Last updated: 2025*
