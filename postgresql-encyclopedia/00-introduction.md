# The PostgreSQL Encyclopedia
## A Comprehensive Guide to the World's Most Advanced Open Source Database

---

## Preface

This encyclopedic work represents a deep dive into every aspect of the PostgreSQL database management system—from its origins at the University of California, Berkeley in 1986 to its current status as the world's most advanced open source relational database. This is not merely documentation; it is a historical artifact, a technical reference, and a cultural study of one of the most successful open source projects in computing history.

### Purpose and Scope

PostgreSQL is more than software—it is a living testament to the power of academic research, community-driven development, and principled engineering. This encyclopedia aims to document:

1. **Technical Architecture**: Every subsystem, from the parser to the storage engine
2. **Historical Evolution**: How the codebase evolved from POSTGRES to PostgreSQL
3. **Cultural Dynamics**: The community, decision-making processes, and development culture
4. **Implementation Details**: Actual source code with file paths and line numbers
5. **Design Philosophy**: The "why" behind architectural decisions

### Who This Is For

This work is designed for:

- **Database Internals Researchers**: Those studying DBMS implementation
- **PostgreSQL Contributors**: Developers joining or already contributing to the project
- **System Architects**: Those evaluating PostgreSQL for large-scale deployments
- **Computer Science Students**: Learning database systems implementation
- **Database Administrators**: Understanding the engine beneath the hood
- **Software Historians**: Studying successful open source projects

### Methodology

This encyclopedia was created through:

1. **Source Code Analysis**: Deep exploration of 2,292 C source files totaling 116MB
2. **Historical Research**: Analysis of commit history, mailing list archives, and community documents
3. **Web Research**: Study of PostgreSQL's development culture and decision-making processes
4. **Documentation Review**: Examination of 324,358 lines of SGML documentation
5. **Community Insights**: Research into the people and processes that shaped PostgreSQL

---

## Chapter 1: What is PostgreSQL?

### 1.1 Definition and Core Characteristics

**PostgreSQL** (pronounced "post-gress-cue-ell") is an object-relational database management system (ORDBMS) that emphasizes:

- **Extensibility**: Users can define custom data types, operators, functions, and even index access methods
- **Standards Compliance**: Implements much of SQL:2016, including advanced features
- **ACID Compliance**: Full support for Atomicity, Consistency, Isolation, and Durability
- **MVCC**: Multi-Version Concurrency Control for high concurrency without read locks
- **Reliability**: Decades of development focused on data integrity
- **Open Source**: Liberal PostgreSQL License (BSD-style)

### 1.2 Official Names Throughout History

The system has been known by several names:

1. **POSTGRES** (1986-1994): "POSTgres" - Post-Ingres, the successor to Ingres
2. **Postgres95** (1994-1996): When SQL support was added
3. **PostgreSQL** (1996-present): Official name reflecting SQL capabilities
4. **Informal**: Often called just "Postgres" by the community

From the COPYRIGHT file:

```
PostgreSQL Database Management System
(also known as Postgres, formerly known as Postgres95)

Portions Copyright (c) 1996-2025, PostgreSQL Global Development Group
Portions Copyright (c) 1994, The Regents of the University of California
```

### 1.3 Key Statistics (Current Codebase)

**Codebase Size:**
- Source directory: 116 MB
- C source files: 2,292 files
- Lines of code: Millions across all components
- Documentation: 324,358 lines of SGML

**Major Components:**
- Backend subsystems: 30+ directories in `src/backend/`
- Utilities: 22+ command-line tools in `src/bin/`
- Contrib modules: 61 extension modules
- Interfaces: libpq, ECPG, and more

**Contributors (Recent History):**
- Top recent contributors: Michael Paquier, Bruce Momjian, Nathan Bossart, Tom Lane
- Thousands of contributors over nearly 40 years
- Active development in multiple continents and time zones

### 1.4 What Makes PostgreSQL Different

#### Compared to Other Open Source Databases

**vs. MySQL:**
- **Extensibility**: PostgreSQL allows custom types, operators, and index methods
- **Standards**: More complete SQL standard implementation
- **MVCC**: True MVCC without locking readers
- **Data Integrity**: Stronger emphasis on ACID compliance
- **Architecture**: Cleaner separation of concerns

**vs. SQLite:**
- **Scale**: PostgreSQL designed for concurrent multi-user access
- **Client/Server**: Network-capable with robust authentication
- **Features**: Advanced features like replication, partitioning, parallel query
- **Extensibility**: Plugin architecture

#### Compared to Commercial Databases

**vs. Oracle:**
- **Cost**: Free and open source
- **License**: Liberal license allows any use
- **Community**: Open development process
- **Innovation**: Faster adoption of new features (e.g., JSON, JSONB)

**vs. Microsoft SQL Server:**
- **Portability**: Runs on Linux, macOS, Windows, BSD
- **Licensing**: No per-core or per-user costs
- **Extensibility**: More open to customization

### 1.5 Core Features

#### Data Types

PostgreSQL supports an extensive range of data types:

**Numeric:**
- Integer types: smallint, integer, bigint
- Arbitrary precision: numeric/decimal
- Floating point: real, double precision
- Serial types: auto-incrementing integers

**Character:**
- varchar(n), char(n), text
- Full Unicode support

**Binary:**
- bytea (binary data)
- Large objects

**Date/Time:**
- date, time, timestamp, interval
- Timezone awareness
- Infinite and -infinite values

**Boolean:**
- true, false, null

**Geometric:**
- point, line, lseg, box, path, polygon, circle

**Network:**
- inet, cidr (IP addresses)
- macaddr (MAC addresses)

**Bit Strings:**
- bit(n), bit varying(n)

**Text Search:**
- tsvector, tsquery for full-text search

**JSON:**
- json (text storage)
- jsonb (binary storage with indexing)

**Arrays:**
- Any data type can be an array

**Range Types:**
- int4range, int8range, numrange, tsrange, daterange
- Custom range types supported

**UUID:**
- Universally Unique Identifiers

**XML:**
- Native XML storage and processing

**Custom Types:**
- Users can define their own types

#### Query Capabilities

**Basic SQL:**
- SELECT, INSERT, UPDATE, DELETE, MERGE
- Joins: INNER, LEFT, RIGHT, FULL, CROSS
- Subqueries and CTEs (WITH clauses)
- UNION, INTERSECT, EXCEPT

**Advanced SQL:**
- Window functions (OVER clause)
- Recursive queries (WITH RECURSIVE)
- Lateral joins
- Grouping sets, CUBE, ROLLUP
- VALUES clauses

**Full-Text Search:**
- Built-in text search with ranking
- Multiple languages supported
- Custom dictionaries

**JSON Querying:**
- Path expressions
- Containment operators
- Indexable with GIN indexes

#### Indexes

**Index Types:**
1. **B-tree**: Default, general-purpose
2. **Hash**: Equality operations
3. **GiST**: Generalized Search Tree (geometric, full-text)
4. **GIN**: Generalized Inverted Index (arrays, JSONB, full-text)
5. **SP-GiST**: Space-Partitioned GiST (non-balanced trees)
6. **BRIN**: Block Range Index (large correlated tables)
7. **Bloom**: Bloom filter (PostgreSQL 10+)

**Index Features:**
- Partial indexes (with WHERE clause)
- Expression indexes
- Multi-column indexes
- Covering indexes (INCLUDE clause)
- Concurrent index creation

#### Transactions and Concurrency

**ACID Properties:**
- **Atomicity**: All-or-nothing execution
- **Consistency**: Database remains in valid state
- **Isolation**: Concurrent transactions don't interfere
- **Durability**: Committed data persists

**Isolation Levels:**
- READ UNCOMMITTED (treated as READ COMMITTED)
- READ COMMITTED (default)
- REPEATABLE READ
- SERIALIZABLE (true serializability via SSI)

**MVCC Benefits:**
- Readers never block writers
- Writers never block readers
- High concurrency with consistency

**Locking:**
- Row-level locking
- Table-level locking with multiple modes
- Advisory locks for application coordination

#### Replication

**Physical Replication:**
- Streaming replication (WAL-based)
- Cascading replication
- Synchronous and asynchronous modes
- Hot standby (read queries on replicas)

**Logical Replication:**
- Row-level replication
- Selective table replication
- Cross-version replication
- Bi-directional replication (with BDR extension)

**Point-in-Time Recovery (PITR):**
- WAL archiving
- Recovery to specific time/transaction
- Backup and restore capabilities

#### Extensibility

**Custom Data Types:**
- Define new types with operators
- Input/output functions
- Type modifiers

**Custom Functions:**
- SQL, PL/pgSQL, C, Python, Perl, Tcl, etc.
- Set-returning functions
- Window functions
- Aggregate functions

**Procedural Languages:**
- PL/pgSQL (default)
- PL/Python
- PL/Perl
- PL/Tcl
- PL/Java (external)
- PL/R (external)

**Foreign Data Wrappers:**
- Query external data sources
- file_fdw, postgres_fdw built-in
- Many third-party FDWs (MySQL, Oracle, MongoDB, etc.)

**Custom Access Methods:**
- Define new index types
- Bloom filter example in contrib

**Hooks:**
- Planner, executor, and utility hooks
- Extensive customization points

---

## Chapter 2: Historical Context

### 2.1 The Berkeley POSTGRES Era (1986-1994)

#### Origins: Post-Ingres

**POSTGRES** was conceived as the successor to INGRES (Interactive Graphics and Retrieval System), which Michael Stonebraker developed at UC Berkeley in the 1970s. After commercializing Ingres and returning to Berkeley in 1985, Stonebraker wanted to address limitations he saw in relational databases of the time.

**Key Innovations Planned:**
1. **Complex Objects**: Beyond simple relational tuples
2. **User Extensibility**: Custom types and operators
3. **Active Databases**: Rules and triggers
4. **Time Travel**: Temporal queries (later removed)
5. **Crash Recovery**: Modern transaction processing

#### The DARPA Years

**Funding:** The project was sponsored by:
- Defense Advanced Research Projects Agency (DARPA)
- Army Research Office (ARO)
- National Science Foundation (NSF)
- ESL, Inc.

**Timeline:**
- **1986**: Implementation begins
- **1987**: First "demoware" system operational
- **1988**: Demonstration at ACM-SIGMOD Conference
- **1989**: Version 1 released to external users (June)
- **1990**: Version 2 with redesigned rule system (June)
- **1991**: Version 3 with multiple storage managers
- **1992-1994**: Version 4.x series, final Berkeley versions

**Original Query Language:**
Early POSTGRES used PostQUEL, not SQL. PostQUEL was a query language based on QUEL (used in Ingres) with extensions for the new features.

**Example PostQUEL:**
```sql
retrieve (emp.name, emp.salary)
where emp.dept = "sales"
```

### 2.2 The Transition: Postgres95 (1994-1996)

#### Adding SQL

In 1994, **Andrew Yu and Jolly Chen** (UC Berkeley graduate students) added an SQL language interpreter to POSTGRES. This was a crucial step toward broader adoption.

**Key Changes:**
- Replaced PostQUEL with SQL
- Maintained underlying POSTGRES architecture
- Made the system more accessible to SQL users
- Performance improvements

**First Release:**
- **Version 0.01**: Announced to beta testers, May 5, 1995
- **Version 1.0**: Public release, September 5, 1995

**Name:** The project was called "Postgres95" to indicate:
- Based on POSTGRES
- Released in 1995
- SQL support added

### 2.3 PostgreSQL: The Open Source Era (1996-Present)

#### The Rename

By 1996, it became clear that "Postgres95" wouldn't stand the test of time. The community chose **PostgreSQL** to reflect:
- Heritage from POSTGRES
- SQL language support
- Professional, lasting name

**First PostgreSQL Version:** 6.0 (January 29, 1997)

The version number started at 6.0 to continue the sequence from the Berkeley POSTGRES project (versions 1-4.2) and Postgres95 (version ~5).

#### The Development Model Changes

**Pre-Internet Era (1986-1995):**
- University-led research project
- Limited external collaboration
- Academic publication-driven
- Periodic snapshot releases

**Internet Era (1996-present):**
- Distributed worldwide development
- Mailing list-based collaboration
- Community-driven decision making
- Regular release cycle

#### The PostgreSQL Global Development Group

**Formation:**
The PostgreSQL Global Development Group (PGDG) formed organically as an informal organization of volunteers.

**Structure:**
- **Core Team**: 7 long-time members handling releases, infrastructure, difficult decisions
- **Committers**: ~20-30 people with direct commit access
- **Major Contributors**: Hundreds of regular contributors
- **Patch Authors**: Thousands over the years

**Decision Making:**
- Consensus-driven
- Public discussion on mailing lists
- Technical merit over politics
- "Rough consensus and running code"

**No Benevolent Dictator:**
Unlike many open source projects, PostgreSQL has no single leader. Decisions emerge from community discussion.

### 2.4 Major Version Milestones

#### Version 6.x Series (1997-1998)

**6.0 (January 1997):**
- First official PostgreSQL release
- Multi-version concurrency control (MVCC) foundation

**6.1-6.5:**
- Performance improvements
- Bug fixes
- Growing community

#### Version 7.x Series (1999-2004)

**7.0 (May 2000):**
- Foreign key support
- SQL92 join syntax
- Optimizer improvements
- Write-ahead logging (WAL) foundation

**7.1 (April 2001):**
- Outer joins
- Improved toast (large object storage)

**7.2 (February 2002):**
- Schema support
- Internationalization improvements

**7.3 (November 2002):**
- Prepared queries in protocol
- Internationalization improvements

**7.4 (November 2003):**
- Improved optimizer
- Multi-column indexes

#### Version 8.x Series (2005-2010)

**8.0 (January 2005):**
- **Native Windows support** (major milestone)
- Point-in-time recovery (PITR)
- Tablespaces
- Savepoints

**8.1 (November 2005):**
- Two-phase commit
- Table partitioning improvements
- Bitmap index scans

**8.2 (December 2006):**
- Warm standby
- Online index builds
- GIN indexes

**8.3 (February 2008):**
- Full-text search integrated
- XML support
- Heap-only tuples (HOT)
- Enum types

**8.4 (July 2009):**
- Windowing functions
- Common table expressions (CTEs)
- Parallel restore
- Column permissions

#### Version 9.x Series (2010-2016)

**9.0 (September 2010):**
- **Hot standby** (read queries on replicas)
- **Streaming replication**
- In-place upgrades (pg_upgrade)
- VACUUM FULL rewrite
- Anonymous code blocks

**9.1 (September 2011):**
- Synchronous replication
- Per-column collations
- Unlogged tables
- Foreign data wrappers
- Extensions

**9.2 (September 2012):**
- Cascading replication
- JSON datatype
- Index-only scans
- pg_stat_statements

**9.3 (September 2013):**
- Writeable foreign data wrappers
- Custom background workers
- Materialized views
- JSON functions

**9.4 (December 2014):**
- **JSONB** (binary JSON with indexing)
- Logical replication foundation
- Replication slots
- REFRESH MATERIALIZED VIEW CONCURRENTLY

**9.5 (January 2016):**
- UPSERT (INSERT ... ON CONFLICT)
- Row-level security
- BRIN indexes
- TABLESAMPLE
- GROUPING SETS

**9.6 (September 2016):**
- Parallel sequential scans
- Parallel joins
- Parallel aggregates
- Synchronous replication improvements
- Multiple standbys

#### Version 10 and Beyond (2017-Present)

**10 (October 2017):**
- **Declarative partitioning**
- Logical replication (publish/subscribe)
- Improved parallelism
- Quorum-based synchronous replication
- SCRAM-SHA-256 authentication
- ICU collation support

**11 (October 2018):**
- Stored procedures (CALL command)
- Improved partitioning
- Parallelism improvements
- JIT compilation (LLVM-based)
- Covering indexes

**12 (October 2019):**
- Generated columns
- JSON path queries
- Pluggable table storage
- Partitioning improvements
- CTE inlining

**13 (September 2020):**
- Parallel vacuum
- Incremental sorting
- Partitioning improvements
- B-tree deduplication
- Extended statistics

**14 (September 2021):**
- Pipeline mode in libpq
- Stored procedures with OUT parameters
- Multirange types
- Subscripting custom types
- JSON subscripting

**15 (October 2022):**
- MERGE command
- Regular expression improvements
- Improved compression
- Public schema permissions change
- Archive library modules

**16 (September 2023):**
- Parallelism improvements
- Logical replication improvements
- SQL/JSON improvements
- pg_stat_io view
- Incremental backups

**17 (September 2024):**
- Incremental backup improvements
- Vacuum improvements
- JSON improvements
- MERGE RETURNING

**Version Numbering Change:**
Starting with version 10, PostgreSQL adopted a simpler numbering scheme:
- **Old:** 9.6, 9.7, etc.
- **New:** 10, 11, 12, etc.
- Minor versions: 10.1, 10.2, etc.

### 2.5 The Hardware Context

Understanding PostgreSQL's evolution requires understanding the hardware constraints of each era.

#### 1986: The VAX Era

**Typical System:**
- DEC VAX minicomputer
- 1-16 MB RAM
- 100-500 MB disk storage
- No SMP (symmetric multiprocessing)
- Tape backups

**Impact on Design:**
- Memory management critical
- Buffer management essential
- Single-process architecture adequate

#### 1990s: Unix Workstations

**Typical System:**
- Sun SPARCstation or SGI Indigo
- 16-128 MB RAM
- 1-10 GB disk
- Early SMP (2-4 CPUs)
- CD-ROM

**Impact on Design:**
- Multi-process model emerges
- Shared memory for buffer cache
- Process-per-connection model

#### 2000s: Commodity Servers

**Typical System:**
- Intel Xeon servers
- 1-16 GB RAM
- 100 GB - 1 TB disk
- 2-8 cores
- RAID controllers

**Impact on Design:**
- WAL optimization for reliability
- Query optimization improvements
- Lock partitioning for concurrency

#### 2010s: Modern Servers

**Typical System:**
- Multi-socket Xeon servers
- 64 GB - 1 TB RAM
- SSDs becoming common
- 16-64 cores
- 10 Gbps networking

**Impact on Design:**
- Parallel query execution
- NUMA awareness
- Lock-free algorithms
- JIT compilation

#### 2020s: Cloud Era

**Typical System:**
- Cloud VMs (AWS, Azure, GCP)
- 1 GB to several TB RAM
- NVMe SSDs
- Elastic scaling
- Object storage integration

**Impact on Design:**
- Pluggable storage
- Cloud-native features
- Incremental backups
- Better resource isolation

---

## Chapter 3: The Community and Culture

### 3.1 Development Process

#### The Commitfest System

**What is a CommitFest?**
A commitfest is a month-long period focused on reviewing patches rather than developing new features. Typically held 4-5 times per development cycle.

**Purpose:**
- Ensure all submitted work gets reviewed
- Prevent patch backlog
- Fair treatment of all contributors
- Quality control through peer review

**Rules:**
- Patch authors expected to review others' patches
- Reviews should be thorough and constructive
- Patches can be: committed, rejected, returned with feedback, or moved to next CF

**Commitfest Manager:**
- Volunteer role
- Coordinates reviews
- Tracks patch status
- Reports progress

**App:** [commitfest.postgresql.org](https://commitfest.postgresql.org)

#### Mailing Lists

**Primary Lists:**
- **pgsql-hackers**: Development discussion (highest traffic)
- **pgsql-bugs**: Bug reports
- **pgsql-general**: User questions
- **pgsql-admin**: Administration topics
- **pgsql-performance**: Performance tuning
- **pgsql-docs**: Documentation

**Culture:**
- Technical discussions can be blunt
- Expect rigorous criticism of ideas
- Personal attacks not tolerated
- Archive is permanent (accurate history)

**Archives:** Available back to 1997

#### Decision Making

**Consensus Model:**
1. Proposal posted to pgsql-hackers
2. Community discussion
3. Objections raised and addressed
4. Rough consensus emerges
5. Committer makes final call

**Core Team Role:**
- Rarely intervenes in technical decisions
- Handles release management
- Resolves conflicts when consensus fails
- Manages infrastructure

**No BDFL:**
Unlike many projects, no single person has final say. Tom Lane is often seen as "first among equals" due to his technical expertise and long history, but he doesn't have dictatorial power.

### 3.2 Key Contributors

#### The "Big Names"

**Tom Lane:**
- Most prolific contributor (82,565 emails to mailing lists)
- 15 emails per day average for over 20 years
- Top committer
- Query optimizer expert
- Known for thorough code reviews

**Bruce Momjian:**
- One of original core team members
- Advocacy and community building
- Documentation
- Release management
- Public face of PostgreSQL for many years

**Magnus Hagander:**
- Windows port maintainer
- Infrastructure management
- Replication features
- Community infrastructure

**Andres Freund:**
- Performance optimization
- JIT compilation
- Query execution
- Low-level optimization

**Peter Eisentraut:**
- Internationalization
- Build system
- SQL standards
- Long-time contributor

**Robert Haas:**
- Parallel query execution
- Partitioning
- Logical replication
- Performance features

#### Corporate Participation

**Companies Supporting Development:**
- EnterpriseDB (EDB)
- Crunchy Data
- 2ndQuadrant (now part of EDB)
- Red Hat
- Fujitsu
- VMware
- Microsoft
- Amazon Web Services
- Google Cloud

**Corporate Policy:**
- Core team members can't all work for same company
- Prevents single-company control
- Maintains independence

### 3.3 Cultural Values

#### Technical Excellence

**Code Quality:**
- Rigorous review process
- High standards for commits
- Extensive testing required
- Performance considerations

**Correctness First:**
- Data integrity paramount
- Conservative about changes
- Backwards compatibility valued
- Deprecation cycles for changes

#### Transparency

**Public Development:**
- All discussion on public mailing lists
- No private decision making
- Commit messages detailed
- Design documents published

**Open Archives:**
- Mailing list archives permanent
- Commit history preserved
- Mistakes documented
- Learning from history

#### Inclusivity (with Roughness)

**Meritocracy:**
- Ideas judged on technical merit
- Contributions welcome from anyone
- No gatekeeping based on affiliation
- Newcomers treated same as veterans

**Direct Communication:**
- Blunt technical criticism normal
- Not personal attacks
- Focus on ideas, not people
- Can feel harsh to newcomers

**From the wiki:**
> "Our discussions can come across as insulting or overly critical. As a new contributor, you are encountering a new culture."

#### Long-Term Thinking

**Sustainability:**
- Features designed to last decades
- API stability important
- On-disk format changes rare
- Upgrade path always provided

**Technical Debt:**
- Actively managed
- Refactoring happens
- Legacy code improved over time
- But stability valued

---

## About This Encyclopedia

This work represents hundreds of hours of code exploration, historical research, and careful documentation. Each chapter contains:

- **Actual source code** with file paths and line numbers
- **Data structures** from the real codebase
- **Algorithms** as implemented
- **Historical context** for design decisions
- **Cross-references** between related topics

The goal is to create the definitive reference for anyone seeking to understand PostgreSQL deeply—from its humble beginnings at Berkeley to its current status as the world's most advanced open source database.

---

**Navigation:**

- **Next Chapter**: [Storage Layer Architecture](01-storage-layer.md)
- **Jump to**: [Table of Contents](README.md)
- **Index**: [Comprehensive Index](appendices/index.md)
- **Glossary**: [PostgreSQL Terminology](appendices/glossary.md)
