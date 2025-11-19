# PostgreSQL Encyclopedia: Comprehensive Alphabetical Index

A comprehensive, alphabetically organized index of all major PostgreSQL concepts, data structures, functions, utilities, and contributors referenced throughout this encyclopedia.

---

## A

**Access Method (AM)**
→ Pluggable interface for implementing index types or table storage
→ See: [Query Processing - Index Types](../02-query-processing/query-pipeline.md), [Storage - Page Layout](../01-storage/storage-layer.md)
→ Types: B-tree, Hash, GiST, GIN, SP-GiST, BRIN, Bloom

**ACID Properties**
→ Atomicity, Consistency, Isolation, Durability - the four transaction guarantees
→ See: [Introduction - Core Features](../00-introduction.md#15-core-features)

**Aggregate Functions**
→ Functions computing a single result from multiple input rows (SUM, AVG, COUNT, etc.)
→ See: [Query Processing - Executor](../02-query-processing/query-pipeline.md)

**Analyzer**
→ Query processing stage performing semantic analysis
→ File: `src/backend/parser/analyze.c`
→ Converts parse tree to query tree with validation

**Autovacuum**
→ Background process automatically performing VACUUM and ANALYZE
→ See: [Process Architecture - Auxiliary Processes](../05-processes/process-architecture.md)
→ Configurable via GUC parameters: autovacuum, autovacuum_naptime

**Auxiliary Processes**
→ Background worker processes (bgwriter, checkpointer, walwriter, autovacuum, etc.)
→ See: [Process Architecture](../05-processes/process-architecture.md)

---

## B

**Backend Process**
→ Server process dedicated to handling a single client connection
→ File: `src/backend/postmaster/postgres.c`
→ Lifecycle: fork → authentication → query processing loop

**Base Backup**
→ Complete copy of database cluster taken while running
→ Created using `pg_basebackup` utility
→ Used for point-in-time recovery and standby creation

**Benchmarking (pgbench)**
→ Utility for performance testing with TPC-B-like workloads
→ File: `src/bin/pgbench/pgbench.c`
→ See: [Utilities - pgbench](../07-utilities/utility-programs.md)

**Berkeley POSTGRES**
→ Original research database at UC Berkeley (1986-1994)
→ Created by Michael Stonebraker
→ Predecessor to PostgreSQL with PostQUEL query language

**bgwriter (Background Writer)**
→ Process that writes dirty buffers from shared memory to disk
→ File: `src/backend/postmaster/bgwriter.c`
→ Smooths I/O load preventing sudden flush storms

**Bitmap Index Scan**
→ Index scan method building bitmap of matching tuples before heap access
→ Efficient for multiple index conditions
→ See: [Query Processing - Index Scans](../02-query-processing/query-pipeline.md)

**BKI (Backend Interface)**
→ Format for bootstrap data files creating initial system catalogs
→ Files: `src/include/catalog/postgres.bki`
→ See: [Build System - Bootstrap](../09-build-system-and-portability.md)

**Bloom Index**
→ Probabilistic index type using Bloom filters
→ Compact, space-efficient for large bitmaps
→ Available in contrib module

**Block/Page**
→ Fundamental 8KB unit of storage organization
→ Standard size configurable at compile time (1, 2, 4, 8, 16, 32 KB)
→ See: [Storage - Page Structure](../01-storage/storage-layer.md)

**Block Range Index (BRIN)**
→ Compact index storing summaries (min/max) for page ranges
→ Excellent for correlated data in large tables
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**BRIN Index**
→ See: Block Range Index

**B-tree**
→ Default index type implementing Lehman and Yao high-concurrency B+ tree
→ File: `src/backend/access/nbtree/`
→ Optimal for range queries and equality searches

**Buffer**
→ In-memory copy of a disk page managed by buffer manager
→ Part of buffer pool (shared_buffers)
→ See: [Storage - Buffer Manager](../01-storage/storage-layer.md)

**BufferDesc**
→ C structure representing buffer pool entry metadata
→ File: `src/include/storage/buf_internals.h`
→ Contains: page content, usage count, pins, locks, LSN

**Buffer Manager**
→ Subsystem managing buffer pool with clock-sweep replacement algorithm
→ File: `src/backend/storage/buffer/bufmgr.c` (7,468 lines)
→ See: [Storage - Buffer Management](../01-storage/storage-layer.md)

**Buffer Pool**
→ Collection of shared memory buffers for caching disk pages
→ Size: controlled by `shared_buffers` GUC parameter
→ See: [Storage - Buffer Manager](../01-storage/storage-layer.md)

---

## C

**Catalog System**
→ System tables storing metadata about database objects
→ Key tables: pg_class, pg_attribute, pg_proc, pg_type, etc.
→ File: `src/include/catalog/`
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**Checkpointer**
→ Process performing checkpoints to ensure data durability
→ File: `src/backend/postmaster/checkpointer.c`
→ Flushes dirty buffers and creates recovery points

**Checkpoint**
→ Point in WAL sequence where all data file changes written to disk
→ Enables recovery to that point
→ Seven-phase process: REDO, checkpoint, CLOG, commit, data, sync, done
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**Clock-Sweep**
→ Buffer replacement algorithm approximating LRU with minimal overhead
→ File: `src/backend/storage/buffer/freelist.c`
→ Uses "usage count" and clock hand positions

**CID (Command ID)**
→ Identifier for a command within a transaction
→ Type: 32-bit unsigned integer
→ See: [Storage - MVCC](../01-storage/storage-layer.md)

**CLOG (Commit Log)**
→ Formerly called "commit log", now pg_xact
→ SLRU storing transaction commit status
→ See: [Transactions - Commit Log](../03-transactions/transaction-management.md)

**CLRU (Circular LRU)**
→ See: Clock-Sweep

**Cluster (Database Cluster)**
→ Collection of databases managed by single PostgreSQL server
→ Stored in PGDATA directory
→ See: [Installation - Data Directory](../00-introduction.md)

**Commitfest**
→ Month-long period focused on reviewing patches
→ System for fair patch evaluation
→ See: [Introduction - Community Development](../00-introduction.md#31-development-process)
→ Tool: commitfest.postgresql.org

**Common Table Expression (CTE)**
→ Named subquery defined with WITH clause
→ Can be recursive (WITH RECURSIVE)
→ See: [Query Processing - CTEs](../02-query-processing/query-pipeline.md)

**Connection Pooling**
→ Technique for reusing database connections
→ External tools: PgBouncer, pgPool-II
→ Reduces overhead of process spawning

**Cost Estimation**
→ Process of predicting resource usage for different query plans
→ Uses statistical models and GUC parameters
→ File: `src/backend/optimizer/path/costsize.c` (220,428 lines)
→ See: [Query Processing - Cost Model](../02-query-processing/query-pipeline.md)

**Cost Model Parameters**
→ GUC variables controlling planner cost estimation
→ Key parameters: seq_page_cost, random_page_cost, cpu_operator_cost
→ See: [Query Processing - Cost Model](../02-query-processing/query-pipeline.md)

**CREATE DATABASE**
→ SQL command to create new database
→ Creates new catalog entry and data directories
→ See: [SQL - DDL](../00-introduction.md)

**CREATE EXTENSION**
→ SQL command to install extension
→ Loads control file and executes SQL script
→ See: [Extensions - Extension System](../06-extensions/extension-system.md)

**CREATE INDEX**
→ SQL command to create index
→ Supports multiple index types and options
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**CREATE TABLE**
→ SQL command to create table
→ Registers in pg_class and related catalogs
→ See: [SQL - DDL](../00-introduction.md)

**CRC32C**
→ Cyclic Redundancy Check for data integrity
→ Hardware-accelerated: SSE4.2, ARM, AVX-512
→ Used in WAL and page checksums

**ctid**
→ System column containing tuple's physical location
→ Format: (page_number, tuple_index)
→ See: [Storage - Tuple Format](../01-storage/storage-layer.md)

---

## D

**Data Directory (PGDATA)**
→ Directory containing all database files, configuration, and WAL
→ Set by initdb command
→ See: [Process Architecture - Postmaster](../05-processes/process-architecture.md)

**Data Structure Node Types**
→ Uniform handling for copying, serialization, and debugging
→ Implemented with T_* macros and switch statements
→ File: `src/include/nodes/nodes.h`

**Database Cluster**
→ See: Cluster

**Database Independence**
→ PostgreSQL design allowing multiple databases in one cluster
→ Each database has independent namespace
→ See: [Introduction - Architecture](../00-introduction.md)

**DARPA**
→ Defense Advanced Research Projects Agency
→ Funded original Berkeley POSTGRES research (1986-1992)
→ See: [Introduction - Historical Context](../00-introduction.md#22-the-berkeley-postgres-era)

**Deadlock**
→ Circular wait condition where transactions block each other
→ Detected by deadlock detection process
→ Resolved by aborting one transaction
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

**Deadlock Detection**
→ Process detecting circular waits in lock graph
→ File: `src/backend/storage/lmgr/deadlock.c`
→ Builds wait-for graph and finds cycles

**DELETE**
→ SQL command to remove rows from table
→ Implemented via heap_delete() function
→ Marks tuples as deleted (MVCC-aware)
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**Direct I/O**
→ I/O operations bypassing kernel cache
→ Not default in PostgreSQL (uses OS cache)
→ Requires platform support

**Dirty Buffer**
→ Buffer whose content differs from disk page
→ Written to disk by bgwriter or checkpointer
→ See: [Storage - Buffer Manager](../01-storage/storage-layer.md)

**Disk Drive Organization**
→ See: Page Structure, Block

**DTM (Dynamic Transaction Manager)**
→ Distributed transaction coordination (in Postgres-XL extensions)
→ Not in core PostgreSQL

---

## E

**Effective User ID**
→ Unix user ID determining session privileges
→ Set via SECURITY DEFINER functions
→ See: [Security - Authentication](../05-processes/process-architecture.md)

**Eisentraut, Peter**
→ Long-time PostgreSQL contributor
→ Expertise: Internationalization, build system, SQL standards
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Encoding Support**
→ Multi-byte character encoding support
→ Supported: UTF-8, LATIN1, EUC_JP, etc.
→ Configured per database
→ See: [Build System - Internationalization](../09-build-system-and-portability.md)

**ENUM Type**
→ Custom data type for enumerated values
→ Introduced in PostgreSQL 8.3
→ Ordered, comparable with indexes supported
→ See: [Introduction - Data Types](../00-introduction.md#15-core-features)

**Event Handling**
→ Mechanism for process event notification
→ File: `src/backend/storage/lmgr/latch.c`
→ WaitEventSet API for efficient event waiting

**Executor**
→ Query processing stage executing plans
→ File: `src/backend/executor/execMain.c` (2,833 lines)
→ See: [Query Processing - Executor](../02-query-processing/query-pipeline.md)

**Execution Nodes**
→ Data structures representing plan execution steps
→ File: `src/include/nodes/execnodes.h`
→ Types: SeqScanState, HashJoinState, etc.

**Executor Hooks**
→ Extensibility points allowing plan modification during execution
→ See: [Extensions - Hooks](../06-extensions/extension-system.md)

**Extension Control File**
→ File specifying extension metadata and dependencies
→ Format: `extension_name.control`
→ Location: `SHAREDIR/extension/`
→ See: [Extensions - Extension System](../06-extensions/extension-system.md)

**Extension System**
→ Mechanism for adding custom functionality without modifying core
→ Supports: custom types, operators, functions, index methods, hooks
→ See: [Extensions - Extension System](../06-extensions/extension-system.md)

**External Sorting**
→ Sorting algorithm for data exceeding work_mem
→ Uses temporary disk files for spillover
→ Implemented with merge phases
→ See: [Query Processing - Executor](../02-query-processing/query-pipeline.md)

---

## F

**Failure Scenarios**
→ Designed resilience against: power loss, system crash, disk failure
→ Mitigated by WAL, checksums, replication
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**FDW (Foreign Data Wrapper)**
→ Interface for querying external data sources
→ Built-in: postgres_fdw, file_fdw
→ See: [Extensions - Foreign Data Wrappers](../06-extensions/extension-system.md)

**FIFO (First In First Out)**
→ Queue discipline used in some systems (not buffer manager)
→ See: Clock-Sweep

**File Organization**
→ Heap files: tuples appended sequentially
→ Index files: structured by access method
→ See: [Storage](../01-storage/storage-layer.md)

**First Normal Form (1NF)**
→ No repeating groups of attributes
→ Assumed in relational databases
→ See: [Introduction - Core Concepts](../00-introduction.md)

**Foreign Key**
→ Constraint enforcing referential integrity
→ Referencing column(s) must exist in referenced table
→ See: [Introduction - Constraints](../00-introduction.md#15-core-features)

**Fork (Table Fork)**
→ Separate physical file for table relation
→ Types: main, init, fsm, vm
→ See: [Storage - Page Structure](../01-storage/storage-layer.md)

**Free Space Map (FSM)**
→ Tracks available space in heap pages for INSERT operations
→ File: `src/backend/storage/freespace/freespace.c`
→ SLRU-based variable-length encoding
→ See: [Storage - Free Space Map](../01-storage/storage-layer.md)

**Freund, Andres**
→ PostgreSQL core contributor
→ Expertise: Performance optimization, JIT compilation, query execution
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Full Table Scan**
→ Sequential scan reading all tuples from heap
→ Fallback when no suitable index exists
→ See: [Query Processing - Executor](../02-query-processing/query-pipeline.md)

**Full-Text Search**
→ Built-in text search with ranking
→ Uses tsvector and tsquery types
→ Multiple languages supported with custom dictionaries
→ See: [Introduction - Data Types](../00-introduction.md#15-core-features)

---

## G

**GiN (Generalized Inverted Index)**
→ Index type for arrays, JSONB, and full-text search
→ Structure: inverted index
→ File: `src/backend/access/gin/`
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**GiST (Generalized Search Tree)**
→ Framework for creating custom index types
→ Used for geometric, full-text, and range queries
→ File: `src/backend/access/gist/`
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Global Development Group (PostgreSQL)**
→ Informal organization managing PostgreSQL development
→ Structure: Core Team (7 members) + Committers (~20-30) + Contributors
→ Decision-making: Consensus-driven, no BDFL
→ See: [Introduction - Community](../00-introduction.md#32-key-contributors)

**Glossary**
→ Comprehensive terminology reference
→ See: [Appendices - Glossary](glossary.md)

**GRANTs**
→ SQL command to assign privileges to roles
→ Granularity: database, schema, table, column
→ See: [SQL - Privileges](../00-introduction.md)

**Grammar (Bison)**
→ SQL language grammar definition
→ File: `src/backend/parser/gram.y` (17,896 lines)
→ Produces parse tree from token stream
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

**GRP (Group)**
→ File permissions group ownership
→ PostgreSQL processes typically run as 'postgres' user
→ See: [Security - File Permissions](../05-processes/process-architecture.md)

**GUC (Grand Unified Configuration)**
→ Unified configuration parameter system
→ Parameters: PGC_POSTMASTER, PGC_SIGHUP, PGC_BACKEND, PGC_USER
→ File: `src/backend/utils/misc/guc.c`
→ See: [Configuration Parameters](#configuration-parameters-section)

---

## H

**Hagander, Magnus**
→ PostgreSQL core contributor
→ Expertise: Windows port, infrastructure, replication
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Hash Index**
→ Index type for equality operations
→ Structure: hash table with chaining
→ File: `src/backend/access/hash/`
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Hash Join**
→ Join algorithm using in-memory hash table
→ Efficient for joining large relations
→ See: [Query Processing - Join Algorithms](../02-query-processing/query-pipeline.md)

**Heap**
→ Storage system for table data (relations)
→ Unordered collection of tuples
→ Access method: heap_scan, heap_insert, heap_update, heap_delete
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**heap_delete**
→ Function removing tuple from heap
→ File: `src/backend/access/heap/heapam.c`
→ Marks tuple deleted, updates indexes
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**heap_insert**
→ Function inserting tuple into heap
→ File: `src/backend/access/heap/heapam.c`
→ Returns TID of inserted tuple for index creation
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**heap_update**
→ Function updating tuple in heap
→ File: `src/backend/access/heap/heapam.c`
→ MVCC-aware, handles HOT optimization
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**Heap-Only Tuple (HOT)**
→ Optimization for updates not changing indexed columns
→ Chains tuples on same page without index updates
→ Reduces index bloat and I/O
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**HeapTupleHeaderData**
→ C structure for tuple header metadata
→ File: `src/include/access/htup_details.h`
→ Contains: transaction IDs, infomask, attribute offset
→ See: [Storage - Tuple Structure](../01-storage/storage-layer.md)

**HOT (Heap-Only Tuple)**
→ See: Heap-Only Tuple

**Hot Standby**
→ Feature allowing read queries on physical replica
→ Requires standby_mode = on
→ Conflicts resolved by canceling queries
→ See: [Replication - Hot Standby](../04-replication/replication-recovery.md)

**Hot Standby Feedback**
→ Mechanism preventing standby queries from blocking master VACUUM
→ Sends oldest non-write-only XID back to master
→ See: [Replication - Hot Standby](../04-replication/replication-recovery.md)

---

## I

**Index**
→ Data structure optimizing data access for specific columns/expressions
→ Types: B-tree, Hash, GiST, GIN, SP-GiST, BRIN, Bloom
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Index Access Method**
→ Interface for implementing custom index types
→ See: Access Method (AM)

**Index Bloat**
→ Accumulation of dead entries in index pages
→ Mitigated by HOT optimization and REINDEX
→ See: [Storage - Heap-Only Tuple](../01-storage/storage-layer.md)

**Index-Only Scan**
→ Index scan returning all result columns directly
→ Does not access heap pages (when visibility map allows)
→ See: [Query Processing - Index Scans](../02-query-processing/query-pipeline.md)

**Ingres**
→ Interactive Graphics and Retrieval System
→ Predecessor to POSTGRES by Michael Stonebraker
→ See: [Introduction - Historical Context](../00-introduction.md#22-the-berkeley-postgres-era)

**initdb**
→ Utility creating new PostgreSQL database cluster
→ File: `src/bin/initdb/initdb.c`
→ Creates system catalogs and bootstrap database
→ See: [Utilities - initdb](../07-utilities/utility-programs.md)

**Inline Function**
→ User-defined function inlined into query plan
→ Requires LANGUAGE sql and IMMUTABLE designation
→ See: [Extensions - Functions](../06-extensions/extension-system.md)

**INSERT**
→ SQL command adding rows to table
→ Executes heap_insert() for each row
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**INSERT ... ON CONFLICT**
→ Upsert command (MERGE alternative)
→ Introduced in PostgreSQL 9.5
→ Specifies action on unique constraint violation
→ See: [Introduction - SQL Features](../00-introduction.md)

**Isolation Level**
→ Level of consistency for concurrent transactions
→ Levels: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE
→ Default: READ COMMITTED
→ See: [Transactions - Isolation Levels](../03-transactions/transaction-management.md)

**ItemIdData**
→ C structure for item pointer (line pointer)
→ File: `src/include/storage/itemid.h`
→ Maps logical tuple ID to physical offset
→ See: [Storage - Item Pointers](../01-storage/storage-layer.md)

**ItemPointer**
→ Logical pointer to tuple location
→ Type: (block_number, offset_number)
→ Provides indirection enabling page defragmentation
→ See: [Storage - Item Pointers](../01-storage/storage-layer.md)

---

## J

**JIT Compilation**
→ Just-In-Time compilation of expressions to machine code
→ Uses LLVM
→ Controlled by: jit, jit_above_cost, jit_inline_above_cost
→ Introduced in PostgreSQL 11
→ See: [Query Processing - Expression Evaluation](../02-query-processing/query-pipeline.md)

**JOIN**
→ SQL operation combining rows from multiple tables
→ Types: INNER, LEFT, RIGHT, FULL, CROSS
→ Algorithms: Nested Loop, Hash Join, Merge Join
→ See: [Query Processing - Join Algorithms](../02-query-processing/query-pipeline.md)

**JSON/JSONB**
→ JSON data types with indexing support
→ json: text storage, JSONB: binary with indexing
→ Introduced: JSON (8.2), JSONB (9.4)
→ See: [Introduction - Data Types](../00-introduction.md#15-core-features)

---

## K

**Key-Value Store**
→ NoSQL pattern sometimes compared to PostgreSQL with JSONB
→ PostgreSQL more structured with ACID guarantees
→ See: [Introduction - Features](../00-introduction.md)

**Keyword**
→ Reserved SQL word recognized by parser
→ File: `src/backend/parser/keywords.c`
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

---

## L

**Lane, Tom**
→ Most prolific PostgreSQL contributor (82,565 mailing list emails)
→ Expertise: Query optimizer, code review
→ Seen as "first among equals" in decision-making
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Latch**
→ Efficient inter-process communication mechanism
→ File: `src/backend/storage/lmgr/latch.c`
→ Allows event-driven waiting without busy loops
→ See: [Process Architecture - IPC](../05-processes/process-architecture.md)

**Lateral Join**
→ Join allowing right-hand side to reference left columns
→ Used with set-returning functions
→ Introduced in PostgreSQL 9.3
→ See: [Query Processing - Join Algorithms](../02-query-processing/query-pipeline.md)

**Lehman and Yao B-Tree**
→ High-concurrency B-tree algorithm used by PostgreSQL
→ Allows lock-free searches during tree modification
→ See: [Storage - B-tree Index](../01-storage/storage-layer.md)

**Lexer**
→ Tokenizer converting SQL text to token stream
→ File: `src/backend/parser/scan.l` (Flex-based)
→ Handles keywords, identifiers, literals, operators
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

**Line Pointer**
→ See: ItemPointer

**Locking**
→ Mechanism for controlling concurrent access to data
→ Three-tier system: spinlocks, LWLocks, heavyweight locks
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

**Log Sequence Number (LSN)**
→ Byte offset in WAL stream identifying position
→ Type: uint64
→ Used for recovery, replication, MVCC
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**Logical Decoding**
→ Process extracting logical changes from WAL
→ Foundation for logical replication
→ File: `src/backend/replication/logical/`
→ See: [Replication - Logical Replication](../04-replication/replication-recovery.md)

**Logical Replication**
→ Row-level replication of logical changes
→ Selective table replication across versions
→ Introduced in PostgreSQL 10
→ See: [Replication - Logical Replication](../04-replication/replication-recovery.md)

**LSN**
→ See: Log Sequence Number

**LWLock (Lightweight Lock)**
→ Efficient lock for shared memory synchronization
→ File: `src/backend/storage/lmgr/lwlock.c`
→ Spinlock + wait queue
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

---

## M

**Mailing Lists**
→ Primary communication channel for PostgreSQL development
→ Key lists: pgsql-hackers, pgsql-bugs, pgsql-general, pgsql-performance, pgsql-admin
→ Archives: searchable, permanent record
→ See: [Introduction - Development Process](../00-introduction.md#31-development-process)

**Materialized View**
→ View with stored result set
→ Requires manual refresh (or REFRESH ... CONCURRENTLY)
→ Introduced in PostgreSQL 9.3
→ See: [SQL - Views](../00-introduction.md)

**Maximum Transaction ID (MAXOID)**
→ Upper bound on transaction ID values
→ 32-bit: 2^31 - 1 (approximately 2 billion)
→ Wraparound managed via vacuum
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**Merge Join**
→ Join algorithm using pre-sorted inputs
→ Efficient for sorted data or large joins
→ See: [Query Processing - Join Algorithms](../02-query-processing/query-pipeline.md)

**Merge Statement**
→ SQL command for conditional insert/update
→ Equivalent to upsert
→ Introduced in PostgreSQL 15
→ See: [Introduction - SQL Features](../00-introduction.md)

**Metadata**
→ Data about data (catalog information)
→ Stored in system tables (pg_class, pg_attribute, etc.)
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**Michael Stonebraker**
→ Creator of POSTGRES and Ingres
→ Turing Award winner
→ Academic advisor to PostgreSQL's founding
→ See: [Introduction - Historical Context](../00-introduction.md#22-the-berkeley-postgres-era)

**Minmax Index**
→ See: BRIN Index

**Momjian, Bruce**
→ PostgreSQL core team member
→ Expertise: Advocacy, community building, documentation
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Modulo Arithmetic**
→ Used for transaction ID comparison
→ Handles XID wraparound with modulo-2^32
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**Meson Build System**
→ Alternative build system to Autoconf
→ Faster, more maintainable configuration
→ Used as primary in PostgreSQL 15+
→ See: [Build System - Meson](../09-build-system-and-portability.md)

**MVCC (Multi-Version Concurrency Control)**
→ Concurrency control mechanism allowing readers and writers to coexist
→ Each transaction sees consistent snapshot
→ Implemented via transaction IDs and tuple visibility rules
→ See: [Storage - MVCC](../01-storage/storage-layer.md)

---

## N

**Nested Loop Join**
→ Join algorithm comparing every row of left to right table
→ Simplest but potentially slowest algorithm
→ See: [Query Processing - Join Algorithms](../02-query-processing/query-pipeline.md)

**Node Types**
→ Unified data structure representation in query trees
→ File: `src/include/nodes/nodes.h`
→ Include: Query, Plan, Expr, Var, Const, etc.
→ See: [Query Processing - Node Types](../02-query-processing/query-pipeline.md)

**Normalization**
→ Process of organizing data to reduce redundancy
→ Normal forms: 1NF, 2NF, 3NF, BCNF, 4NF, 5NF
→ See: [Introduction - Concepts](../00-introduction.md)

**NOT NULL Constraint**
→ Constraint requiring column to have non-NULL value
→ Enforced at insertion and update
→ See: [SQL - Constraints](../00-introduction.md)

**Number of Tuples**
→ Cardinality statistic used in cost estimation
→ Updated by ANALYZE command
→ Stored in pg_stats view
→ See: [Query Processing - Cost Model](../02-query-processing/query-pipeline.md)

---

## O

**Object-Relational Database**
→ Relational database with object-oriented features
→ Supports custom types, operators, inheritance
→ PostgreSQL: full ORDBMS
→ See: [Introduction - Definition](../00-introduction.md#11-definition-and-core-characteristics)

**ORDBMS**
→ See: Object-Relational Database

**On-Disk Format**
→ Physical layout of data in files
→ Stable across versions (with upgrade mechanisms)
→ See: [Storage - Page Structure](../01-storage/storage-layer.md)

**Operator**
→ Comparison, arithmetic, or string operation
→ User-definable with custom implementations
→ Index types determine supported operators
→ See: [Introduction - Extensibility](../00-introduction.md)

**Operator Family**
→ Group of operators working with same index type
→ File: `src/backend/catalog/pg_opfamily.h`
→ Enables multiple operators for one index
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Option (Command-line)**
→ Flags passed to PostgreSQL utilities
→ See individual utilities: pg_dump, pg_restore, psql, etc.
→ See: [Utilities](../07-utilities/utility-programs.md)

**Optimizer**
→ Query processing component selecting execution plans
→ Cost-based: chooses lowest estimated cost plan
→ File: `src/backend/optimizer/` (~220,428 lines)
→ See: [Query Processing - Planner](../02-query-processing/query-pipeline.md)

**ORDER BY**
→ SQL clause specifying sort order
→ Implemented via external sort or index-based ordering
→ See: [Query Processing - Sorting](../02-query-processing/query-pipeline.md)

---

## P

**Page**
→ See: Block/Page

**PageHeaderData**
→ C structure containing page metadata
→ File: `src/include/storage/bufpage.h`
→ Contains: LSN, checksum, flags, offsets, pruning info
→ See: [Storage - Page Header](../01-storage/storage-layer.md)

**Page Layout**
→ Physical organization of data within 8KB page
→ Consists: header, item pointers, free space, tuple data, special space
→ See: [Storage - Page Structure](../01-storage/storage-layer.md)

**Parallel Execution**
→ Query execution using multiple processes/threads
→ Supported: sequential scans, joins, aggregates
→ Introduced in PostgreSQL 9.6
→ Controlled by max_parallel_workers_per_gather
→ See: [Query Processing - Parallel Execution](../02-query-processing/query-pipeline.md)

**Parallel Worker**
→ Process executing portion of parallel query
→ Spawned by main query process
→ See: [Process Architecture - Parallel Workers](../05-processes/process-architecture.md)

**Parameterized Path**
→ Query path with parameters for outer relation values
→ Enables nested loop join optimization
→ See: [Query Processing - Path Planning](../02-query-processing/query-pipeline.md)

**Parser**
→ Query processing stage converting SQL text to parse tree
→ File: `src/backend/parser/` (gram.y, scan.l)
→ Produces Query structure from RawStmt
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

**Paquier, Michael**
→ Recent prolific PostgreSQL contributor
→ Top committer in recent years
→ See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

**Path (Query Path)**
→ Intermediate representation during query planning
→ Describes access method and join method choice
→ File: `src/include/nodes/relationnode.h`
→ See: [Query Processing - Path Planning](../02-query-processing/query-pipeline.md)

**pg_*.c Files (Utilities)**
→ Source code for command-line utilities
→ See: [Utilities - File Locations](#utilities-section)

**pg_analyze_and_rewrite**
→ Function performing semantic analysis and rewriting
→ File: `src/backend/parser/analyze.c`
→ See: [Query Processing - Analysis and Rewriting](../02-query-processing/query-pipeline.md)

**pg_attribute**
→ System catalog storing column definitions
→ One row per table column
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**pg_basebackup**
→ Utility creating base backup for replication setup
→ File: `src/bin/pg_basebackup/pg_basebackup.c`
→ Streams data while server running
→ See: [Utilities - pg_basebackup](../07-utilities/utility-programs.md)

**pg_class**
→ System catalog storing table, index, sequence definitions
→ One row per relation
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**pg_control**
→ File storing cluster state information
→ Location: $PGDATA/global/pg_control
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**pg_ctl**
→ Utility managing PostgreSQL server lifecycle
→ File: `src/bin/pg_ctl/pg_ctl.c`
→ Commands: start, stop, restart, promote, reload
→ See: [Utilities - pg_ctl](../07-utilities/utility-programs.md)

**pg_dump**
→ Utility exporting database to SQL script or archive
→ File: `src/bin/pg_dump/pg_dump.c` (20,570 lines)
→ Formats: plain SQL, custom archive, directory, tar
→ See: [Utilities - pg_dump](../07-utilities/utility-programs.md)

**pg_hba.conf**
→ Host-based authentication configuration file
→ Location: $PGDATA/pg_hba.conf
→ Specifies authentication method for client connections
→ See: [Process Architecture - Authentication](../05-processes/process-architecture.md)

**pg_ident.conf**
→ User mapping configuration file
→ Maps OS users to PostgreSQL users
→ Location: $PGDATA/pg_ident.conf
→ See: [Process Architecture - Authentication](../05-processes/process-architecture.md)

**pg_plan_query**
→ Function performing query planning
→ File: `src/backend/optimizer/planner.c`
→ See: [Query Processing - Planner](../02-query-processing/query-pipeline.md)

**pg_proc**
→ System catalog storing function definitions
→ One row per function
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**pg_restore**
→ Utility restoring database from archive
→ File: `src/bin/pg_dump/pg_restore.c`
→ Parallel restoration with dependency resolution
→ See: [Utilities - pg_restore](../07-utilities/utility-programs.md)

**pg_type**
→ System catalog storing data type definitions
→ One row per data type
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**pg_upgrade**
→ Utility performing in-place cluster upgrade
→ File: `src/bin/pg_upgrade/pg_upgrade.c`
→ Modes: link, copy, clone
→ See: [Utilities - pg_upgrade](../07-utilities/utility-programs.md)

**pg_xact**
→ SLRU directory storing transaction commit status
→ Formerly called "clog" (commit log)
→ Location: $PGDATA/pg_xact/
→ See: [Transactions - Commit Log](../03-transactions/transaction-management.md)

**pgbench**
→ Utility for database performance benchmarking
→ File: `src/bin/pgbench/pgbench.c`
→ Workload: TPC-B-like transactions
→ See: [Utilities - pgbench](../07-utilities/utility-programs.md)

**PGDATA**
→ See: Data Directory

**pgindent**
→ Tool for formatting code to PostgreSQL style
→ See: [Build System - Development Tools](../09-build-system-and-portability.md)

**PostgreSQL**
→ Official name since 1996, reflecting SQL support
→ Earlier names: POSTGRES (1986-1994), Postgres95 (1994-1996)
→ See: [Introduction - Official Names](../00-introduction.md#12-official-names-throughout-history)

**Postgres95**
→ Version adding SQL support to POSTGRES
→ Released 1995, predecessor to PostgreSQL
→ See: [Introduction - Postgres95](../00-introduction.md#22-the-transition-postgres95-1994-1996)

**Postmaster**
→ Main PostgreSQL server process
→ File: `src/backend/postmaster/postmaster.c`
→ Responsibilities: initialization, process spawning, supervision, shutdown
→ See: [Process Architecture - Postmaster](../05-processes/process-architecture.md)

**PostQUEL**
→ Query language used by original POSTGRES
→ Predecessor to SQL in PostgreSQL
→ See: [Introduction - Historical Context](../00-introduction.md#22-the-berkeley-postgres-era)

**Prepared Statement**
→ Pre-parsed and planned SQL statement
→ Reduces parsing/planning overhead
→ Protocol support in PostgreSQL 7.3+
→ See: [Query Processing - Prepared Statements](../02-query-processing/query-pipeline.md)

**PRIMARY KEY**
→ Constraint enforcing unique identification of rows
→ Automatically creates B-tree index
→ See: [SQL - Constraints](../00-introduction.md)

**Privilege**
→ Right to perform action on database object
→ Granularity: database, schema, table, column
→ See: [Security - Privileges](../05-processes/process-architecture.md)

**Procedural Language**
→ Language for writing stored procedures
→ Supported: PL/pgSQL, PL/Python, PL/Perl, PL/Tcl
→ See: [Extensions - Procedural Languages](../06-extensions/extension-system.md)

**Process Architecture**
→ Multi-process design of PostgreSQL
→ Advantages: fault isolation, portability, security, simplicity
→ See: [Process Architecture](../05-processes/process-architecture.md)

**procarray.c**
→ File managing process array and snapshot building
→ Contains GetSnapshotData() implementation
→ Location: `src/backend/storage/ipc/procarray.c`
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**Publish-Subscribe Replication**
→ Logical replication with flexible subscription
→ Introduced in PostgreSQL 10
→ See: [Replication - Logical Replication](../04-replication/replication-recovery.md)

**psql**
→ Interactive PostgreSQL terminal
→ File: `src/bin/psql/` (80+ meta-commands)
→ Features: tab completion, history, formatted output
→ See: [Utilities - psql](../07-utilities/utility-programs.md)

**Pruning (HOT Pruning)**
→ Process removing old tuple versions from page
→ Optimization: keeps page reference without index updates
→ See: [Storage - Heap-Only Tuple](../01-storage/storage-layer.md)

---

## Q

**Query**
→ SQL statement requesting data
→ Processing: parse → rewrite → plan → execute
→ See: [Query Processing - Overview](../02-query-processing/query-pipeline.md)

**Query Planner**
→ See: Optimizer

**Query Processing Pipeline**
→ Four stages: parse, rewrite, plan, execute
→ File: `src/backend/` (parser, rewriter, optimizer, executor)
→ See: [Query Processing](../02-query-processing/query-pipeline.md)

**Query Rewriter**
→ Stage handling view expansion and rule application
→ File: `src/backend/rewrite/rewriteHandler.c` (3,877 lines)
→ See: [Query Processing - Rewriter](../02-query-processing/query-pipeline.md)

**Query Tree**
→ Intermediate representation after parsing
→ Contains Query structure with semantic information
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

---

## R

**Range Type**
→ Data type representing range of values
→ Examples: int4range, int8range, daterange, tsrange
→ User-definable custom ranges
→ Introduced in PostgreSQL 9.2
→ See: [Introduction - Data Types](../00-introduction.md#15-core-features)

**RawStmt**
→ Raw parse tree node before semantic analysis
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

**Read Committed**
→ Default isolation level
→ Sees committed data only
→ Does not prevent dirty reads of uncommitted writes
→ See: [Transactions - Isolation Levels](../03-transactions/transaction-management.md)

**Read Uncommitted**
→ Isolation level treated as READ COMMITTED in PostgreSQL
→ See: [Transactions - Isolation Levels](../03-transactions/transaction-management.md)

**Recovery**
→ Process restoring database after failure
→ Uses WAL to replay transactions up to failure point
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**Recovery Target**
→ Point to recover to (XID, timestamp, LSN, etc.)
→ See: [Replication - Point-In-Time Recovery](../04-replication/replication-recovery.md)

**Recursive Query**
→ See: Common Table Expression (WITH RECURSIVE)

**Reindex**
→ Process rebuilding index from scratch
→ Utility: reindexdb
→ See: [Utilities - reindexdb](../07-utilities/utility-programs.md)

**Relation**
→ Database object with named columns and tuples (table, index, sequence)
→ Stored in pg_class catalog
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**Replication**
→ Process of maintaining copies of data on multiple servers
→ Types: physical (WAL-based), logical (row-level)
→ See: [Replication](../04-replication/replication-recovery.md)

**Replication Slot**
→ Mechanism preventing WAL deletion for a logical consumer
→ Maintains retention information
→ See: [Replication - Replication Slots](../04-replication/replication-recovery.md)

**ReorderBuffer**
→ Structure managing transaction ordering for logical replication
→ Ensures consistent snapshots for logical changes
→ See: [Replication - Logical Replication](../04-replication/replication-recovery.md)

**REPEATABLE READ**
→ Isolation level guaranteeing repeatable reads
→ Does not prevent phantom reads
→ See: [Transactions - Isolation Levels](../03-transactions/transaction-management.md)

**REPLICA IDENTITY**
→ Information identifying tuples for logical replication
→ Types: DEFAULT (primary key), FULL (all columns), NOTHING (unavailable)
→ See: [Replication - Logical Replication](../04-replication/replication-recovery.md)

**Replicator**
→ See: WAL sender

**Resource Manager**
→ Component managing system resources
→ Example: buffer manager
→ See: [Storage - Buffer Manager](../01-storage/storage-layer.md)

**REVOKE**
→ SQL command removing privileges from role
→ See: [Security - Privileges](../05-processes/process-architecture.md)

**Rewrite**
→ See: Query Rewriter

**Rewriter**
→ See: Query Rewriter

**Role**
→ Database user or group with privileges
→ Can be login user or group for privilege aggregation
→ See: [Security - Roles](../05-processes/process-architecture.md)

**Row-Level Security (RLS)**
→ Feature restricting row access based on role
→ Policies checked at query execution time
→ See: [Security - Row-Level Security](../05-processes/process-architecture.md)

**Row Locking**
→ Locking at individual row level
→ FOR UPDATE, FOR SHARE in SELECT
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

---

## S

**Safe Shutdown**
→ Smart or Fast shutdown mode
→ See: Shutdown Modes

**Savepoint**
→ Named point within transaction for partial rollback
→ Introduced in PostgreSQL 7.4
→ See: [Transactions - Savepoints](../03-transactions/transaction-management.md)

**Scalability**
→ Ability to increase performance with more hardware
→ Challenges: lock contention, cache coherency
→ Addressed by: partitioning, parallel execution, lock-free algorithms
→ See: [Query Processing - Parallel Execution](../02-query-processing/query-pipeline.md)

**Scan (Table Scan)**
→ Access method reading table data
→ Types: sequential scan, index scan, bitmap scan
→ See: [Query Processing - Scans](../02-query-processing/query-pipeline.md)

**SCRAM-SHA-256**
→ Salted Challenge Response Authentication Mechanism
→ Default authentication method since PostgreSQL 10
→ See: [Process Architecture - Authentication](../05-processes/process-architecture.md)

**Segment (WAL Segment)**
→ Fixed-size WAL file (typically 16 MB)
→ Location: $PGDATA/pg_wal/
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**SELECT**
→ SQL command querying data
→ Processing: parse → rewrite → plan → execute
→ See: [Query Processing - Overview](../02-query-processing/query-pipeline.md)

**Sequence**
→ Database object generating unique identifier values
→ Relation type in pg_class
→ See: [Introduction - Data Types](../00-introduction.md)

**Sequential Scan**
→ Access method reading all heap pages sequentially
→ Fallback when no suitable index exists
→ See: [Query Processing - Scans](../02-query-processing/query-pipeline.md)

**Serializable**
→ Highest isolation level
→ Implemented via Serializable Snapshot Isolation (SSI)
→ See: [Transactions - Isolation Levels](../03-transactions/transaction-management.md)

**Serializable Snapshot Isolation (SSI)**
→ Implementation of true SERIALIZABLE isolation
→ Detects conflicts and aborts transactions
→ Introduced in PostgreSQL 9.1
→ See: [Transactions - Serializable Snapshot Isolation](../03-transactions/transaction-management.md)

**Set Operations**
→ SQL operations on result sets
→ Operations: UNION, INTERSECT, EXCEPT
→ See: [Introduction - SQL Features](../00-introduction.md)

**Shared Memory**
→ Memory accessible to multiple processes
→ Contains buffer pool, lock tables, shared state
→ Size: shared_buffers + miscellaneous overhead
→ See: [Process Architecture - Shared Memory](../05-processes/process-architecture.md)

**Shutdown Modes**
→ PostgreSQL shutdown methods
→ Modes: Smart (waits for connections), Fast (rolls back), Immediate (emergency)
→ See: [Process Architecture - Shutdown](../05-processes/process-architecture.md)

**Signal**
→ IPC mechanism for asynchronous notification
→ Used: SIGHUP (reload config), SIGTERM (shutdown), etc.
→ See: [Process Architecture - IPC](../05-processes/process-architecture.md)

**SLRU (Simple LRU)**
→ Fixed-size LRU cache for catalog data
→ Used for: CLOG, fsm, visibility map, commit log
→ File: `src/backend/access/transam/slru.c`
→ See: [Storage - MVCC](../01-storage/storage-layer.md)

**Snapshot**
→ Consistent view of database at specific transaction point
→ Based on active transaction list
→ See: [Transactions - Snapshots](../03-transactions/transaction-management.md)

**Snapshot Isolation**
→ Each transaction sees consistent snapshot
→ Foundation of MVCC
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**SP-GiST (Space-Partitioned GiST)**
→ Index type for partitioned space (quadtrees, k-d trees)
→ Non-balanced tree structure
→ File: `src/backend/access/spgist/`
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Sparse Index**
→ Index not covering all rows
→ Example: partial index with WHERE clause
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**Spinlock**
→ Lightweight spin-wait lock
→ Used for very short critical sections
→ File: `src/backend/storage/lmgr/spin.c`
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

**SQL**
→ Structured Query Language
→ Supported: SQL:2016 (large subset)
→ See: [Introduction - Core Features](../00-introduction.md)

**SQLSTATE**
→ Error code format (5-character)
→ First two characters: class, last three: condition
→ See: [Error Handling](../05-processes/process-architecture.md)

**Statement**
→ Complete SQL command
→ See: Query

**Statistics**
→ Information about table/index characteristics
→ Used for query planning
→ Updated by ANALYZE
→ Stored in pg_stats view
→ See: [Query Processing - Cost Model](../02-query-processing/query-pipeline.md)

**Stats Collector**
→ Auxiliary process gathering statistics
→ File: `src/backend/postmaster/pgstat.c`
→ Sends updates at intervals
→ See: [Process Architecture - Auxiliary Processes](../05-processes/process-architecture.md)

**Standby**
→ Replica database in replication setup
→ Can be warm standby or hot standby
→ See: [Replication - Hot Standby](../04-replication/replication-recovery.md)

**Stonebraker, Michael**
→ See: Michael Stonebraker

**Storage Format**
→ Physical layout of data on disk
→ See: [Storage - Page Structure](../01-storage/storage-layer.md)

**Stored Procedure**
→ Named PL/pgSQL function with CALL command
→ Introduced in PostgreSQL 11
→ See: [Extensions - Procedural Languages](../06-extensions/extension-system.md)

**Streaming Replication**
→ Physical replication sending WAL records continuously
→ Introduced in PostgreSQL 9.0
→ See: [Replication - Streaming Replication](../04-replication/replication-recovery.md)

**String Literal**
→ Text value in SQL
→ Enclosed in single quotes
→ See: [Query Processing - Parser](../02-query-processing/query-pipeline.md)

**Subquery**
→ Query nested within another query
→ Can appear in SELECT, FROM, WHERE clauses
→ See: [Query Processing - Subqueries](../02-query-processing/query-pipeline.md)

**Syslogger**
→ Auxiliary process managing server logging
→ File: `src/backend/postmaster/syslogger.c`
→ Writes to log files or system logger
→ See: [Process Architecture - Auxiliary Processes](../05-processes/process-architecture.md)

**System Catalog**
→ Set of system tables storing database metadata
→ See: [Query Processing - Catalog System](../02-query-processing/query-pipeline.md)

**System Column**
→ Column automatically provided by PostgreSQL
→ Examples: ctid, oid, xmin, xmax, xvac, cmin, cmax
→ See: [Storage - System Columns](../01-storage/storage-layer.md)

---

## T

**Table**
→ Named relation storing data
→ Access method: heap (default)
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**Table Inheritance**
→ Object-oriented feature allowing table hierarchy
→ Queries can include inherited table data
→ See: [Introduction - Extensibility](../00-introduction.md)

**Table Partitioning**
→ Division of large table into smaller pieces
→ Methods: range, list, hash
→ Introduced: range/list (8.1), hash (11)
→ See: [SQL - Partitioning](../00-introduction.md)

**Table Scan**
→ Reading table data via heap access method
→ See: Sequential Scan, Index Scan

**Tablespace**
→ Logical location for storing database objects
→ Maps to directory on filesystem
→ See: [Storage - Tablespaces](../01-storage/storage-layer.md)

**TABLESAMPLE**
→ SQL clause sampling table rows
→ Methods: BERNOULLI, SYSTEM
→ Introduced in PostgreSQL 9.5
→ See: [Introduction - SQL Features](../00-introduction.md)

**TOAST (The Oversized-Attribute Storage Technique)**
→ System for storing large attribute values
→ Compresses or externalizes values > TOAST_TUPLE_THRESHOLD
→ See: [Storage - TOAST](../01-storage/storage-layer.md)

**TOAST Table**
→ Hidden table storing out-of-line attribute data
→ Created automatically for tables with TOAST-able columns
→ See: [Storage - TOAST](../01-storage/storage-layer.md)

**Transaction**
→ Atomic unit of work with ACID properties
→ Begins: explicitly (BEGIN) or implicitly (first query)
→ Ends: COMMIT or ROLLBACK
→ See: [Transactions](../03-transactions/transaction-management.md)

**Transaction ID (XID)**
→ Unique identifier for transaction
→ 32-bit unsigned integer
→ Special values: 0 (invalid), 1 (bootstrap), 2+ (regular)
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**Transaction Isolation Level**
→ See: Isolation Level

**Tuple**
→ Row in a table
→ Consists of: header + null bitmap + attribute data
→ See: [Storage - Tuple Structure](../01-storage/storage-layer.md)

**Tuple Visibility**
→ Rules determining whether transaction can see tuple version
→ Based on transaction IDs and isolation level
→ See: [Transactions - Tuple Visibility](../03-transactions/transaction-management.md)

**Two-Phase Commit (2PC)**
→ Protocol ensuring consistency in distributed transactions
→ Phases: prepare, commit
→ See: [Transactions - Two-Phase Commit](../03-transactions/transaction-management.md)

**Two-Phase Locking**
→ Locking protocol with growing and shrinking phases
→ Guarantees serializability
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

**Type Coercion**
→ Automatic conversion between compatible types
→ Implicit vs explicit casting
→ See: [Query Processing - Type System](../02-query-processing/query-pipeline.md)

---

## U

**Undo Log**
→ Not used in PostgreSQL
→ MVCC provides similar functionality without undo
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

**UNIQUE Constraint**
→ Constraint enforcing uniqueness of column value
→ Creates B-tree index
→ Allows NULL unless NOT NULL also specified
→ See: [SQL - Constraints](../00-introduction.md)

**UNIQUE Index**
→ Index enforcing uniqueness
→ Created by UNIQUE constraint or explicit CREATE UNIQUE INDEX
→ See: [Storage - Index Access Methods](../01-storage/storage-layer.md)

**UNION**
→ SQL operation combining results of multiple queries
→ Variants: UNION (distinct), UNION ALL
→ See: [Introduction - SQL Features](../00-introduction.md)

**UPDATE**
→ SQL command modifying rows
→ MVCC: creates new tuple versions
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

**Utility Statement**
→ Non-query SQL statement (DDL, DCL)
→ Examples: CREATE, ALTER, GRANT, etc.
→ See: [Query Processing - Utility Handling](../02-query-processing/query-pipeline.md)

**Utility Hooks**
→ Extensibility points for utility statement processing
→ See: [Extensions - Hooks](../06-extensions/extension-system.md)

**UUID**
→ Universally Unique Identifier
→ 128-bit value
→ Requires uuid extension for UUID type
→ See: [Introduction - Data Types](../00-introduction.md)

---

## V

**VACUUM**
→ Maintenance operation removing dead tuples
→ Reclaims disk space and updates statistics
→ Options: FULL (rewrites), FREEZE, ANALYZE, VERBOSE
→ See: [Storage - Maintenance](../01-storage/storage-layer.md)

**Visibility Map (VM)**
→ Bitmap tracking pages with all-visible tuples
→ Optimization for VACUUM and index-only scans
→ File: `src/backend/storage/buffer/visibilitymap.c`
→ See: [Storage - Visibility Map](../01-storage/storage-layer.md)

**View**
→ Named query stored as database object
→ Types: view, materialized view
→ See: [SQL - Views](../00-introduction.md)

**Virtual Transaction ID (Vxid)**
→ Transaction ID for uncommitted transaction
→ Format: (process_id, sequence_number)
→ Not visible to users
→ See: [Transactions - Transaction IDs](../03-transactions/transaction-management.md)

**VirtualXidBuffer**
→ Slotted array tracking virtual transaction IDs
→ File: `src/backend/storage/ipc/procarray.c`
→ See: [Transactions - MVCC](../03-transactions/transaction-management.md)

---

## W

**WAL (Write-Ahead Logging)**
→ Technique ensuring ACID durability
→ All changes written to log before applied to disk
→ File: `src/backend/access/transam/xlog.c` (9,584 lines)
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**WAL Archiving**
→ Process copying completed WAL segments to archive
→ Used for point-in-time recovery
→ See: [Replication - Point-In-Time Recovery](../04-replication/replication-recovery.md)

**WAL Buffer**
→ In-memory buffer for WAL records
→ Flushed to disk by walwriter or COMMIT
→ Size: wal_buffers parameter
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**WAL Record**
→ Log entry describing data modification
→ Contains: type, data, checksum, LSN
→ See: [Storage - Write-Ahead Logging](../01-storage/storage-layer.md)

**WAL Sender**
→ Auxiliary process sending WAL to standby
→ File: `src/backend/replication/walsender.c`
→ One per streaming replication connection
→ See: [Process Architecture - Auxiliary Processes](../05-processes/process-architecture.md)

**WAL Writer**
→ Auxiliary process writing WAL buffer to disk
→ File: `src/backend/postmaster/walwriter.c`
→ Operates at intervals (wal_writer_delay)
→ See: [Process Architecture - Auxiliary Processes](../05-processes/process-architecture.md)

**WHERE Clause**
→ SQL clause filtering rows
→ Conditions applied during execution
→ See: [Query Processing - Filtering](../02-query-processing/query-pipeline.md)

**Window Function**
→ Function operating on set of rows related to current row
→ Clauses: PARTITION BY, ORDER BY, frame specification
→ Examples: ROW_NUMBER, RANK, SUM OVER
→ Introduced in PostgreSQL 8.4
→ See: [Introduction - SQL Features](../00-introduction.md)

**WITH Clause**
→ Common Table Expression definition
→ Can be recursive
→ See: [Query Processing - CTEs](../02-query-processing/query-pipeline.md)

**WITH RECURSIVE**
→ Recursive CTE for hierarchical queries
→ Introduced in PostgreSQL 8.4
→ See: [Query Processing - CTEs](../02-query-processing/query-pipeline.md)

**Worker Pool**
→ Pool of parallel workers available for query execution
→ Size: max_worker_processes
→ See: [Process Architecture - Parallel Workers](../05-processes/process-architecture.md)

**Work Memory**
→ GUC parameter limiting memory per sort/hash operation
→ Parameter: work_mem
→ Exceeding causes disk-based operations
→ See: [Configuration Parameters](#configuration-parameters-section)

**Write Lock**
→ Lock preventing concurrent writes
→ Held during UPDATE, DELETE, INSERT
→ See: [Transactions - Locking](../03-transactions/transaction-management.md)

---

## X

**XID**
→ See: Transaction ID

**xlog**
→ Write-Ahead Log (internal name)
→ See: WAL

---

## Y

**Yu, Andrew**
→ UC Berkeley graduate student
→ Added SQL support to POSTGRES in 1994
→ Co-creator of Postgres95
→ See: [Introduction - Postgres95 Era](../00-introduction.md#22-the-transition-postgres95-1994-1996)

---

## Z

**ZHEAP**
→ Proposed heap storage optimization (experimental)
→ Reduces MVCC overhead
→ See: [Storage - Heap Access Method](../01-storage/storage-layer.md)

---

# Technical Terms and Concepts Cross-Index

## Data Structures

| Structure | File | Purpose |
|-----------|------|---------|
| **PageHeaderData** | `src/include/storage/bufpage.h` | Page metadata |
| **HeapTupleHeaderData** | `src/include/access/htup_details.h` | Tuple header |
| **ItemIdData** | `src/include/storage/itemid.h` | Item pointer (line pointer) |
| **BufferDesc** | `src/include/storage/buf_internals.h` | Buffer pool entry |
| **Query** | `src/include/nodes/parsenodes.h` | Parse/query tree node |
| **Plan** | `src/include/nodes/plannodes.h` | Query plan node |
| **PlanState** | `src/include/nodes/execnodes.h` | Executor state node |
| **Path** | `src/include/nodes/relationnode.h` | Query path node |
| **TupleTableSlot** | `src/include/executor/tuptable.h` | Tuple data container |

See: [Storage - Data Structures](../01-storage/storage-layer.md), [Query Processing - Node Types](../02-query-processing/query-pipeline.md)

---

## Key Functions

| Function | File | Purpose |
|----------|------|---------|
| **heap_insert()** | `src/backend/access/heap/heapam.c` | Insert tuple into heap |
| **heap_update()** | `src/backend/access/heap/heapam.c` | Update tuple in heap |
| **heap_delete()** | `src/backend/access/heap/heapam.c` | Delete tuple from heap |
| **GetSnapshotData()** | `src/backend/storage/ipc/procarray.c` | Build transaction snapshot |
| **pg_analyze_and_rewrite()** | `src/backend/parser/analyze.c` | Analysis and rewriting |
| **pg_plan_query()** | `src/backend/optimizer/planner.c` | Query planning |
| **ExecInitNode()** | `src/backend/executor/execMain.c` | Initialize executor node |
| **ExecProcNode()** | `src/backend/executor/execMain.c` | Execute executor node |
| **LockAcquire()** | `src/backend/storage/lmgr/lock.c` | Acquire lock |
| **CreateCheckPoint()** | `src/backend/access/transam/xlog.c` | Perform checkpoint |

See: [Storage - Heap Functions](../01-storage/storage-layer.md), [Query Processing - Execution](../02-query-processing/query-pipeline.md), [Transactions - Locking](../03-transactions/transaction-management.md)

---

## Configuration Parameters (GUC)

### Memory Parameters
- **shared_buffers** - Size of shared memory buffer pool (default: 128 MB)
- **work_mem** - Memory for sorting/hash (default: 4 MB)
- **maintenance_work_mem** - Memory for VACUUM/CREATE INDEX (default: 64 MB)
- **wal_buffers** - WAL buffer size (default: 16 MB)
- **effective_cache_size** - Planner estimate of OS cache (default: 4 GB)

### I/O Parameters
- **seq_page_cost** - Cost of sequential page fetch (default: 1.0)
- **random_page_cost** - Cost of random page fetch (default: 4.0)
- **cpu_operator_cost** - Cost of expression evaluation (default: 0.0025)
- **effective_io_concurrency** - Prefetch operations (default: 1)

### Query Planning Parameters
- **max_parallel_workers_per_gather** - Parallel workers per Gather node (default: 2)
- **max_parallel_workers** - Total parallel workers (default: 8)
- **jit** - Enable JIT compilation (default: on)
- **jit_above_cost** - Cost threshold for JIT (default: 100000)

### Replication Parameters
- **wal_level** - WAL detail level (default: replica)
- **max_wal_senders** - Maximum streaming connections (default: 3)
- **wal_keep_size** - WAL retention size (default: 0)
- **hot_standby** - Enable read queries on standby (default: on)

### Maintenance Parameters
- **autovacuum** - Enable autovacuum (default: on)
- **autovacuum_naptime** - Time between autovacuum runs (default: 1 min)
- **autovacuum_vacuum_threshold** - Tuples to trigger vacuum (default: 50)
- **autovacuum_analyze_threshold** - Tuples to trigger analyze (default: 50)

See: [Configuration Parameters](../00-introduction.md), [Query Processing - Cost Model](../02-query-processing/query-pipeline.md)

---

## Utilities and Tools

| Utility | File | Purpose |
|---------|------|---------|
| **pg_dump** | `src/bin/pg_dump/pg_dump.c` | Logical backup |
| **pg_restore** | `src/bin/pg_dump/pg_restore.c` | Restore from archive |
| **pg_basebackup** | `src/bin/pg_basebackup/pg_basebackup.c` | Physical backup |
| **psql** | `src/bin/psql/` | Interactive terminal |
| **pg_ctl** | `src/bin/pg_ctl/pg_ctl.c` | Server control |
| **initdb** | `src/bin/initdb/initdb.c` | Initialize cluster |
| **pg_upgrade** | `src/bin/pg_upgrade/pg_upgrade.c` | In-place upgrade |
| **pgbench** | `src/bin/pgbench/pgbench.c` | Performance testing |
| **vacuumdb** | `src/bin/scripts/vacuumdb.c` | Vacuum database |
| **reindexdb** | `src/bin/scripts/reindexdb.c` | Reindex database |
| **clusterdb** | `src/bin/scripts/clusterdb.c` | Cluster tables |

See: [Utilities](../07-utilities/utility-programs.md)

---

## Key Contributors

| Name | Role | Contributions |
|------|------|---------------|
| **Tom Lane** | Core Team | Query optimizer, code review (82,565 emails) |
| **Bruce Momjian** | Core Team | Advocacy, community, documentation |
| **Magnus Hagander** | Core Team | Windows port, infrastructure, replication |
| **Andres Freund** | Core Contributor | Performance, JIT, query execution |
| **Peter Eisentraut** | Long-time | I18n, build system, SQL standards |
| **Robert Haas** | Core Contributor | Parallel query, partitioning, replication |
| **Michael Paquier** | Top Contributor | Recent prolific contributor |
| **Michael Stonebraker** | Founder | Original POSTGRES creator |
| **Andrew Yu** | Historical | Added SQL to POSTGRES |

See: [Introduction - Key Contributors](../00-introduction.md#32-key-contributors)

---

## Version Milestones

| Version | Date | Key Features |
|---------|------|--------------|
| **POSTGRES 1** | June 1989 | First external release |
| **POSTGRES 3** | 1991 | Multiple storage managers |
| **Postgres95 1.0** | Sept 1995 | SQL support added |
| **PostgreSQL 6.0** | Jan 1997 | First official PostgreSQL |
| **7.0** | May 2000 | Foreign keys, WAL foundation |
| **8.0** | Jan 2005 | Native Windows support |
| **8.3** | Feb 2008 | Full-text search, XML, HOT, Enums |
| **9.0** | Sept 2010 | Hot standby, streaming replication |
| **9.1** | Sept 2011 | Synchronous replication, FDW, extensions |
| **9.2** | Sept 2012 | JSON, index-only scans |
| **9.4** | Dec 2014 | JSONB, logical replication foundation |
| **9.5** | Jan 2016 | UPSERT, BRIN, RLS |
| **9.6** | Sept 2016 | Parallel query execution |
| **10** | Oct 2017 | Declarative partitioning, logical replication |
| **11** | Oct 2018 | Stored procedures, JIT compilation |
| **12** | Oct 2019 | Generated columns, pluggable storage |
| **13** | Sept 2020 | Parallel vacuum, incremental sorting |
| **14** | Sept 2021 | Pipeline mode, JSON subscripting |
| **15** | Oct 2022 | MERGE command, regex improvements |
| **16** | Sept 2023 | Parallelism improvements, logical replication |
| **17** | Sept 2024 | Incremental backups, vacuum improvements |

See: [Introduction - Version Milestones](../00-introduction.md#24-major-version-milestones)

---

## Important Source Files

### Core Engine
- **Parser**: `src/backend/parser/gram.y`, `src/backend/parser/scan.l`
- **Planner**: `src/backend/optimizer/planner.c`, `src/backend/optimizer/path/pathnode.c`
- **Executor**: `src/backend/executor/execMain.c`, `src/backend/executor/execTuples.c`
- **Analyzer**: `src/backend/parser/analyze.c`

### Storage
- **Buffer Manager**: `src/backend/storage/buffer/bufmgr.c`
- **Heap Access**: `src/backend/access/heap/heapam.c`
- **WAL**: `src/backend/access/transam/xlog.c`
- **MVCC**: `src/backend/storage/ipc/procarray.c`

### Transactions
- **Locking**: `src/backend/storage/lmgr/lock.c`, `src/backend/storage/lmgr/lwlock.c`
- **Transaction State**: `src/backend/access/transam/xact.c`
- **Snapshot**: `src/backend/storage/ipc/procarray.c`

### Process Management
- **Postmaster**: `src/backend/postmaster/postmaster.c`
- **Backend**: `src/backend/postmaster/postgres.c`
- **Autovacuum**: `src/backend/postmaster/autovacuum.c`

### Index Access Methods
- **B-tree**: `src/backend/access/nbtree/nbtree.c`
- **Hash**: `src/backend/access/hash/hash.c`
- **GiST**: `src/backend/access/gist/gist.c`
- **GIN**: `src/backend/access/gin/ginx.c`

See: [Build System - Source Organization](../09-build-system-and-portability.md)

---

# Index Usage Guide

This comprehensive index is organized alphabetically with cross-references. To locate information:

1. **By Topic**: Look up the main term (e.g., "MVCC", "VACUUM", "Replication")
2. **By File**: Search for source code files (e.g., "bufmgr.c", "xlog.c")
3. **By Function**: Look up C function names (e.g., "heap_insert", "GetSnapshotData")
4. **By Data Structure**: Search for struct names (e.g., "PageHeaderData", "BufferDesc")
5. **By Utility**: Look up command names (e.g., "pg_dump", "psql")
6. **By Person**: Find contributors' names (e.g., "Tom Lane", "Bruce Momjian")
7. **By Version**: Browse version milestones section for feature history

Each entry includes:
- **Definition**: Clear explanation of the concept
- **Location**: File path for source code references
- **Cross-references**: Links to related encyclopedia sections
- **Context**: Usage in PostgreSQL internals

---

**Navigation:**
- **Encyclopedia Home**: [README.md](../README.md)
- **Introduction**: [00-introduction.md](../00-introduction.md)
- **Glossary**: [appendices/glossary.md](glossary.md)
- **Storage Layer**: [01-storage/storage-layer.md](../01-storage/storage-layer.md)
- **Query Processing**: [02-query-processing/query-pipeline.md](../02-query-processing/query-pipeline.md)
- **Transactions**: [03-transactions/transaction-management.md](../03-transactions/transaction-management.md)
- **Replication**: [04-replication/replication-recovery.md](../04-replication/replication-recovery.md)
- **Process Architecture**: [05-processes/process-architecture.md](../05-processes/process-architecture.md)
- **Extensions**: [06-extensions/extension-system.md](../06-extensions/extension-system.md)
- **Utilities**: [07-utilities/utility-programs.md](../07-utilities/utility-programs.md)
- **Build System**: [09-build-system-and-portability.md](../09-build-system-and-portability.md)
- **Evolution**: [08-evolution/historical-evolution.md](../08-evolution/historical-evolution.md)

---

*Last Updated: November 19, 2025*
*PostgreSQL Encyclopedia Version 1.0*
