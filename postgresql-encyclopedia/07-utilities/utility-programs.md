# Chapter 7: PostgreSQL Utility Programs

## Introduction

PostgreSQL provides a comprehensive suite of command-line utilities that facilitate database administration, maintenance, backup and recovery, diagnostics, and performance testing. These utilities are client-side programs that interact with PostgreSQL server instances or data directories to perform specialized tasks. Understanding these tools is essential for effective PostgreSQL administration and development.

The utilities can be categorized into several functional groups:

- **Backup and Restore Tools**: Logical and physical backup solutions
- **Interactive Terminals**: SQL client interfaces
- **Cluster Management**: Database cluster initialization and server control
- **Maintenance Tools**: Routine database maintenance operations
- **Administrative Tools**: Major administrative operations and upgrades
- **Diagnostic Tools**: Troubleshooting and verification utilities
- **Benchmarking Tools**: Performance testing and workload simulation
- **Convenience Tools**: Database and user creation shortcuts

All utilities are located in the PostgreSQL installation's `bin/` directory and share common infrastructure including connection handling, logging, and command-line parsing.

## 1. Backup and Restore Utilities

### 1.1 pg_dump - Logical Backup

**Purpose**: `pg_dump` extracts a PostgreSQL database into a script file or archive file containing SQL commands to reconstruct the database.

**Architecture**: The utility operates as a regular PostgreSQL client, querying system catalogs to extract schema and data information. It runs in a transaction snapshot mode to ensure consistency.

**Key Source Files**:
- `src/bin/pg_dump/pg_dump.c` - Main program logic
- `src/bin/pg_dump/pg_dump.h` - Core data structures
- `src/bin/pg_dump/pg_backup_archiver.c` - Archive format handler
- `src/bin/pg_dump/pg_backup_db.c` - Database connection management
- `src/bin/pg_dump/common.c` - Shared utility functions

**Main Features**:

1. **Multiple Output Formats**:
   - Plain SQL text (default)
   - Custom compressed archive (most flexible)
   - Directory format (parallel dump/restore)
   - Tar archive format

2. **Selective Dumping**:
   - Specific tables, schemas, or databases
   - Schema-only or data-only dumps
   - Exclude patterns and object filtering
   - Filter files for complex selection criteria

3. **Parallel Processing**:
   - Multiple worker processes for directory format
   - Significant speedup for large databases
   - Controlled via `-j` option

4. **Transaction Consistency**:
   - Uses REPEATABLE READ transaction isolation
   - Acquires ACCESS SHARE locks on dumped tables
   - Captures consistent snapshot via `pg_export_snapshot()`

**Implementation Details**:

The dump process follows these phases:

```c
// Simplified pg_dump flow from pg_dump.c
1. setup_connection()      // Connect and set transaction snapshot
2. getSchemaData()         // Read catalog and build dependency graph
3. sortDumpableObjects()   // Topological sort for restore order
4. dumpDumpableObject()    // Output each object definition
```

Key transaction handling from source:
```c
/*
 * Note that pg_dump runs in a transaction-snapshot mode transaction,
 * so it sees a consistent snapshot of the database including system
 * catalogs. However, it relies in part on various specialized backend
 * functions like pg_get_indexdef(), and those things tend to look at
 * the currently committed state.
 */
```

**Usage Examples**:

```bash
# Dump entire database to plain SQL
pg_dump mydb > backup.sql

# Custom format with compression
pg_dump -Fc -Z9 mydb > backup.dump

# Directory format with parallel dump
pg_dump -Fd -j 4 mydb -f backup_dir/

# Schema only (no data)
pg_dump --schema-only mydb > schema.sql

# Specific tables with verbose output
pg_dump -t 'sales_*' -t customers -v mydb > partial.sql

# Exclude specific schemas
pg_dump --exclude-schema=temp --exclude-schema=staging mydb > prod.sql
```

**Backend Integration**:
- Uses libpq for all server communication
- Relies on backend functions: `pg_get_indexdef()`, `pg_get_constraintdef()`, `pg_get_functiondef()`, etc.
- Queries system catalogs: `pg_class`, `pg_attribute`, `pg_constraint`, `pg_index`, etc.

### 1.2 pg_restore - Logical Restore

**Purpose**: `pg_restore` restores a PostgreSQL database from an archive created by pg_dump in non-plain-text format.

**Key Source Files**:
- `src/bin/pg_dump/pg_restore.c` - Main restoration logic
- `src/bin/pg_dump/pg_backup_archiver.c` - Archive reading
- `src/bin/pg_dump/pg_backup_custom.c` - Custom format handler
- `src/bin/pg_dump/pg_backup_directory.c` - Directory format handler

**Main Features**:

1. **Flexible Restoration**:
   - Restore entire archive or specific objects
   - Schema-only or data-only restore
   - Create database or restore into existing one

2. **Parallel Restore**:
   - Multiple parallel jobs (`-j` option)
   - Works with custom and directory formats
   - Respects object dependencies

3. **Table of Contents (TOC) Manipulation**:
   - List archive contents (`-l`)
   - Selective restore via TOC file editing
   - Reordering capabilities

**Basic Process** (from source comments):
```c
/*
 * Basic process in a restore operation is:
 *
 *  Open the Archive and read the TOC.
 *  Set flags in TOC entries, and *maybe* reorder them.
 *  Generate script to stdout
 *  Exit
 */
```

**Usage Examples**:

```bash
# Restore entire database
pg_restore -d newdb backup.dump

# List contents of archive
pg_restore -l backup.dump > toc.list

# Restore with parallel jobs
pg_restore -j 4 -d mydb backup_dir/

# Restore only specific schema
pg_restore -n public -d mydb backup.dump

# Restore data only (schema must exist)
pg_restore --data-only -d mydb backup.dump

# Clean database before restore
pg_restore -c -d mydb backup.dump
```

### 1.3 pg_basebackup - Physical Backup

**Purpose**: `pg_basebackup` takes a base backup of a running PostgreSQL cluster using the streaming replication protocol.

**Key Source Files**:
- `src/bin/pg_basebackup/pg_basebackup.c` - Main program
- `src/bin/pg_basebackup/streamutil.c` - Streaming replication utilities
- `src/bin/pg_basebackup/receivelog.c` - WAL receiving
- `src/bin/pg_basebackup/walmethods.c` - WAL writing methods

**Main Features**:

1. **Physical Backup**:
   - Exact copy of data directory
   - Includes all databases in cluster
   - Point-in-time recovery capable

2. **Streaming Methods**:
   - Plain format (direct file copy)
   - Tar format (compressed archives)
   - Server-side or client-side compression

3. **WAL Streaming**:
   - Concurrent WAL archiving during backup
   - Ensures backup consistency
   - `-X stream` or `-X fetch` modes

4. **Progress Reporting**:
   - Real-time progress indicators
   - Estimated completion time
   - Backup manifest generation (v13+)

**Version Compatibility** (from source):
```c
/*
 * pg_xlog has been renamed to pg_wal in version 10.
 */
#define MINIMUM_VERSION_FOR_PG_WAL  100000

/*
 * Temporary replication slots are supported from version 10.
 */
#define MINIMUM_VERSION_FOR_TEMP_SLOTS 100000

/*
 * Backup manifests are supported from version 13.
 */
#define MINIMUM_VERSION_FOR_MANIFESTS  130000
```

**Usage Examples**:

```bash
# Basic backup to directory
pg_basebackup -D /backup/pgdata -P

# Compressed tar format with WAL
pg_basebackup -D /backup -Ft -z -X stream -P

# Backup with specific compression
pg_basebackup -D /backup -Ft --compress=gzip:9 -X stream

# Use replication slot
pg_basebackup -D /backup -S myslot -X stream -P

# Server-side compression (v15+)
pg_basebackup -D /backup --compress=server-gzip:5 -X stream

# Generate backup manifest
pg_basebackup -D /backup --manifest-checksums=SHA256 -P
```

**Backend Integration**:
- Uses replication protocol (`BASE_BACKUP` command)
- Connects to server with `replication=1` connection string
- Backend code: `src/backend/replication/basebackup.c`
- Requires `pg_read_all_settings` or superuser privilege

### 1.4 pg_verifybackup - Backup Verification

**Purpose**: Verifies the integrity of a base backup against its manifest file.

**Key Source Files**:
- `src/bin/pg_verifybackup/pg_verifybackup.c` - Main verification logic
- `src/bin/pg_verifybackup/parse_manifest.c` - Manifest parsing

**Main Features**:
- Checksum verification of all files
- Detection of missing or extra files
- WAL consistency checking
- Support for tar and plain format backups

**Usage Example**:
```bash
# Verify backup directory
pg_verifybackup /backup/pgdata

# Verify with quiet output
pg_verifybackup -q /backup/pgdata

# Verify and ignore specific files
pg_verifybackup -e 'postgresql.auto.conf' /backup/pgdata
```

## 2. Interactive Terminal - psql

### 2.1 Overview

**Purpose**: `psql` is PostgreSQL's interactive terminal, providing a command-line interface for executing SQL queries, managing database objects, and performing administrative tasks.

**Key Source Files**:
- `src/bin/psql/command.c` (6,560 lines) - Backslash command processing
- `src/bin/psql/describe.c` (7,392 lines) - Object description commands
- `src/bin/psql/common.c` - Query execution and result display
- `src/bin/psql/tab-complete.in.c` - Tab completion logic
- `src/bin/psql/input.c` - Input handling and readline integration
- `src/bin/psql/mainloop.c` - Main REPL loop
- `src/bin/psql/startup.c` - Initialization and startup
- `src/bin/psql/variables.c` - Variable management
- `src/bin/psql/help.c` - Help system

### 2.2 Architecture

**Command Processing**:
```c
// From command.c - command dispatch
static backslashResult exec_command(const char *cmd,
                                    PsqlScanState scan_state,
                                    ConditionalStack cstack,
                                    PQExpBuffer query_buf,
                                    PQExpBuffer previous_buf);
```

psql distinguishes between:
- **SQL commands**: Sent directly to server
- **Meta-commands**: Backslash commands processed locally (80+ commands)
- **psql variables**: Client-side configuration and scripting

### 2.3 Major Command Categories

**Connection Commands**:
- `\c[onnect]` - Connect to different database/server
- `\conninfo` - Display connection information
- `\password` - Change user password

**Description Commands** (`\d` family):
- `\d[S+]` - List tables, views, sequences
- `\dt` - List tables only
- `\di` - List indexes
- `\dv` - List views
- `\df` - List functions
- `\dn` - List schemas
- `\du` - List roles
- `\l` - List databases
- `\dx` - List extensions
- `\d+ tablename` - Detailed table description

**Query Execution Commands**:
- `\g` - Execute query
- `\gx` - Execute query with expanded output
- `\gset` - Execute query and store results in variables
- `\watch` - Execute query repeatedly

**Output Formatting**:
- `\x` - Toggle expanded output
- `\pset` - Set output options (format, border, pager)
- `\t` - Tuples-only mode (no headers)
- `\a` - Toggle aligned/unaligned output
- `\H` - HTML output format
- `\o filename` - Redirect output to file

**Import/Export**:
- `\copy` - Client-side COPY (similar to SQL COPY)
- `\i filename` - Execute commands from file
- `\ir filename` - Execute commands from file (relative path)
- `\o` - Redirect query output

**Editing Commands**:
- `\e` - Edit query buffer in external editor
- `\ef` - Edit function definition
- `\ev` - Edit view definition
- `\p` - Print current query buffer

**Information Commands**:
- `\l` - List databases
- `\encoding` - Show/set client encoding
- `\timing` - Toggle timing of commands
- `\set`/`\unset` - Set/unset psql variables

**Transaction Control**:
- `\begin` - Begin transaction
- `\commit` - Commit transaction
- `\rollback` - Rollback transaction

**Scripting Commands**:
- `\if`, `\elif`, `\else`, `\endif` - Conditional execution
- `\set`/`\unset` - Variable assignment
- `\echo` - Print to stdout
- `\qecho` - Print to query output
- `\warn` - Print warning message
- `\gset` - Store query results in variables
- `\include` - Include another file

**Pipeline Commands** (protocol-level pipelining):
- `\startpipeline` - Start pipeline mode
- `\endpipeline` - End pipeline mode
- `\sync` - Pipeline sync point

### 2.4 Advanced Features

**Tab Completion**:
- SQL keyword completion
- Object name completion (tables, columns, functions)
- Context-aware suggestions
- Implemented in `tab-complete.in.c` using readline library

**Variables and Interpolation**:
```sql
-- Set variable
\set myvar 'value'

-- Use in query
SELECT * FROM :myvar;

-- Conditional execution
\if :myvar
  SELECT 'variable is set';
\endif
```

**Special Variables**:
- `AUTOCOMMIT` - Auto-commit mode
- `ECHO` - Echo executed queries
- `HISTFILE` - Command history file
- `ON_ERROR_STOP` - Stop on errors (important for scripts)
- `PROMPT1/2/3` - Customize prompts
- `VERBOSITY` - Error message verbosity

**Crosstab Reports**:
```sql
-- \crosstabview for pivot-style reports
SELECT year, quarter, sales FROM data \crosstabview
```

### 2.5 Usage Examples

```bash
# Connect to database
psql -h localhost -U myuser -d mydb

# Execute single command
psql -c "SELECT version();" mydb

# Execute script
psql -f setup.sql mydb

# Variable substitution
psql -v tablename=users -f query.sql

# CSV output
psql -c "SELECT * FROM users" --csv mydb > users.csv

# Tuples-only output (scripting)
psql -t -c "SELECT id FROM users" mydb
```

**Interactive Session**:
```sql
-- List all tables with details
\dt+

-- Describe specific table
\d+ users

-- Toggle expanded output
\x

-- Execute query with timing
\timing on
SELECT COUNT(*) FROM large_table;

-- Edit query in $EDITOR
\e

-- Save query results to file
\o results.txt
SELECT * FROM data;
\o

-- Watch query (refresh every 2 seconds)
SELECT COUNT(*) FROM active_sessions \watch 2
```

### 2.6 Backend Integration

psql uses libpq exclusively for all server communication:
- Single connection per session
- Synchronous query execution (with exception of `\watch`)
- Protocol-level features: prepared statements, COPY protocol, pipeline mode
- Meta-commands query system catalogs to generate descriptions

## 3. Cluster Management

### 3.1 initdb - Database Cluster Initialization

**Purpose**: `initdb` creates a new PostgreSQL database cluster (a collection of databases managed by a single server instance).

**Key Source Files**:
- `src/bin/initdb/initdb.c` - Complete initialization logic
- Embeds `postgres.bki` - System catalog bootstrap data
- Uses shared `findtimezone.c` for timezone detection

**Architecture**:

From source comments:
```c
/*
 * initdb creates (initializes) a PostgreSQL database cluster (site,
 * instance, installation, whatever).  A database cluster is a
 * collection of PostgreSQL databases all managed by the same server.
 *
 * To create the database cluster, we create the directory that contains
 * all its data, create the files that hold the global tables, create
 * a few other control files for it, and create three databases: the
 * template databases "template0" and "template1", and a default user
 * database "postgres".
 *
 * The template databases are ordinary PostgreSQL databases.  template0
 * is never supposed to change after initdb, whereas template1 can be
 * changed to add site-local standard data.  Either one can be copied
 * to produce a new database.
 */
```

**Initialization Process**:

1. **Bootstrap Phase**:
   - Run postgres in bootstrap mode
   - Load `postgres.bki` to create system catalogs
   - Create template1 database

2. **Post-Bootstrap Phase**:
   - Execute SQL scripts to populate catalogs
   - Install procedural languages
   - Create information_schema
   - Set up system views

3. **Template Database Creation**:
   - Copy template1 to create template0
   - Create default "postgres" database
   - Freeze template0 (make read-only template)

**Main Features**:

1. **Authentication Configuration**:
   - Support for various auth methods (trust, md5, scram-sha-256, peer, ident)
   - Configurable via `--auth`, `--auth-host`, `--auth-local`
   - Generates `pg_hba.conf`

2. **Locale and Encoding**:
   - Database locale (`--locale`)
   - Character encoding (`--encoding`)
   - ICU locale support (`--icu-locale`)
   - Collation settings

3. **Data Checksums**:
   - Optional page-level checksums (`--data-checksums`)
   - Cannot be changed after initialization

4. **WAL Configuration**:
   - WAL segment size (`--wal-segsize`, default 16MB)
   - Set at initialization, cannot change without rebuild

**Usage Examples**:

```bash
# Basic initialization
initdb -D /var/lib/postgresql/data

# With specific encoding and locale
initdb -D /data/pgdata --encoding=UTF8 --locale=en_US.UTF-8

# Enable data checksums
initdb -D /data/pgdata --data-checksums

# Custom WAL segment size (must be power of 2)
initdb -D /data/pgdata --wal-segsize=32

# Specific authentication
initdb -D /data/pgdata --auth=scram-sha-256 --auth-host=scram-sha-256

# With ICU locale
initdb -D /data/pgdata --locale-provider=icu --icu-locale=en-US

# Specify superuser
initdb -D /data/pgdata -U postgres
```

**Generated Directory Structure**:
```
pgdata/
├── base/           # Per-database subdirectories
├── global/         # Cluster-wide tables
├── pg_wal/         # WAL files
├── pg_xact/        # Transaction status
├── pg_multixact/   # MultiXact data
├── pg_commit_ts/   # Commit timestamps
├── pg_stat/        # Statistics
├── pg_tblspc/      # Tablespace links
├── postgresql.conf # Main configuration
├── pg_hba.conf    # Host-based authentication
├── pg_ident.conf  # User name mapping
└── PG_VERSION     # Version file
```

### 3.2 pg_ctl - PostgreSQL Server Control

**Purpose**: `pg_ctl` is a utility to start, stop, restart, reload, and check the status of a PostgreSQL server.

**Key Source Files**:
- `src/bin/pg_ctl/pg_ctl.c` - All control operations

**Architecture**:

**Shutdown Modes** (from source):
```c
typedef enum
{
    SMART_MODE,      // Wait for clients to disconnect
    FAST_MODE,       // Disconnect clients, rollback transactions
    IMMEDIATE_MODE,  // Abort without clean shutdown (requires crash recovery)
} ShutdownMode;
```

**Commands**:
```c
typedef enum
{
    NO_COMMAND = 0,
    INIT_COMMAND,       // Run initdb
    START_COMMAND,      // Start server
    STOP_COMMAND,       // Stop server
    RESTART_COMMAND,    // Stop and start
    RELOAD_COMMAND,     // SIGHUP (reload config)
    STATUS_COMMAND,     // Check status
    PROMOTE_COMMAND,    // Promote standby to primary
    LOGROTATE_COMMAND,  // Rotate log file
    KILL_COMMAND,       // Send signal to server
} CtlCommand;
```

**Main Features**:

1. **Server Lifecycle**:
   - Start server with optional wait for readiness
   - Stop server with configurable shutdown mode
   - Restart server (stop + start)
   - Reload configuration without restart

2. **Status Monitoring**:
   - Check if server is running
   - Wait for server startup/shutdown
   - Configurable timeout

3. **Promotion**:
   - Promote standby server to primary
   - Creates `promote` trigger file

4. **Log Management**:
   - Specify log file location
   - Log rotation support

**Usage Examples**:

```bash
# Start PostgreSQL server
pg_ctl -D /var/lib/postgresql/data start

# Start with specific log file
pg_ctl -D /data/pgdata -l /var/log/postgresql.log start

# Stop server (fast mode - default)
pg_ctl -D /data/pgdata stop

# Stop with smart shutdown (wait for clients)
pg_ctl -D /data/pgdata stop -m smart

# Stop immediately (may require crash recovery)
pg_ctl -D /data/pgdata stop -m immediate

# Restart server
pg_ctl -D /data/pgdata restart

# Reload configuration
pg_ctl -D /data/pgdata reload

# Check status
pg_ctl -D /data/pgdata status

# Promote standby to primary
pg_ctl -D /data/pgdata promote

# Start and wait for server ready (30 second timeout)
pg_ctl -D /data/pgdata -w -t 30 start

# Rotate log file
pg_ctl -D /data/pgdata logrotate
```

**Platform-Specific Features**:
- **Unix/Linux**: Uses signals (SIGTERM, SIGINT, SIGQUIT)
- **Windows**: Service registration and management

**Integration with Backend**:
- Reads `postmaster.pid` for process information
- Reads `pg_control` for cluster state
- Creates trigger files for promotion
- Sends SIGHUP for configuration reload

## 4. Maintenance Tools

PostgreSQL provides client-side wrappers around SQL maintenance commands for convenient administration.

### 4.1 vacuumdb - Vacuum Database

**Purpose**: Wrapper around the SQL `VACUUM` command for reclaiming storage and updating statistics.

**Key Source Files**:
- `src/bin/scripts/vacuumdb.c` - Main program
- `src/bin/scripts/vacuuming.c` - Vacuum operation logic
- `src/bin/scripts/vacuuming.h` - Shared definitions

**Main Features**:

1. **Vacuum Operations**:
   - Standard vacuum (reclaim space)
   - Full vacuum (reclaim and compact)
   - Analyze (update statistics)
   - Analyze-only (no vacuuming)

2. **Parallel Processing**:
   - Multiple parallel workers (`-j` option)
   - Per-table or per-database parallelization

3. **Advanced Options**:
   - Freeze tuples (aggressive freezing)
   - Skip locked tables
   - Disable page skipping
   - Index cleanup control
   - Process main/toast selectively

**Usage Examples**:

```bash
# Vacuum entire database
vacuumdb mydb

# Vacuum and analyze
vacuumdb -z mydb

# Analyze only
vacuumdb -Z mydb

# Full vacuum
vacuumdb --full mydb

# All databases
vacuumdb -a

# Specific tables with parallel workers
vacuumdb -t users -t orders -j 4 mydb

# Verbose output
vacuumdb -v mydb

# Freeze tuples (aggressive)
vacuumdb --freeze mydb

# Skip locked tables
vacuumdb --skip-locked -a

# Minimum XID age threshold
vacuumdb --min-xid-age 1000000 mydb

# Analyze in stages (for minimal disruption)
vacuumdb --analyze-in-stages mydb

# Disable index cleanup
vacuumdb --no-index-cleanup mydb

# Specific schema
vacuumdb -n public mydb

# Exclude schema
vacuumdb -N temp mydb
```

**Backend Integration**:
- Executes SQL `VACUUM` statements via libpq
- Can use multiple database connections for parallelism
- Backend implementation: `src/backend/commands/vacuum.c`

### 4.2 reindexdb - Rebuild Indexes

**Purpose**: Wrapper around the SQL `REINDEX` command for rebuilding indexes.

**Key Source Files**:
- `src/bin/scripts/reindexdb.c` - Main logic

**Main Features**:

1. **Reindex Targets**:
   - Entire database
   - Specific schemas
   - Specific tables
   - Specific indexes
   - System catalogs only

2. **Parallel Reindexing**:
   - Multiple parallel connections
   - Table-level parallelism

3. **Concurrent Reindex**:
   - CONCURRENTLY option (minimal locking)
   - Safe for production systems

**Usage Examples**:

```bash
# Reindex entire database
reindexdb mydb

# Reindex system catalogs
reindexdb --system mydb

# Reindex specific table
reindexdb -t users mydb

# Reindex specific index
reindexdb -i users_pkey mydb

# Concurrent reindex (minimal locking)
reindexdb --concurrently -t large_table mydb

# All databases
reindexdb -a

# Parallel reindex
reindexdb -j 4 mydb

# Specific schema
reindexdb -S public mydb

# With tablespace relocation
reindexdb --tablespace fast_ssd -t hot_table mydb
```

### 4.3 clusterdb - Cluster Tables

**Purpose**: Wrapper around the SQL `CLUSTER` command for reordering table data based on an index.

**Key Source Files**:
- `src/bin/scripts/clusterdb.c` - Implementation

**Main Features**:

1. **Table Clustering**:
   - Reorder table data to match index order
   - Improves sequential scan performance
   - Requires table rewrite

2. **Selective Clustering**:
   - Specific tables only
   - All previously clustered tables
   - Entire database

**Usage Examples**:

```bash
# Cluster entire database
clusterdb mydb

# Cluster specific table
clusterdb -t users mydb

# Cluster multiple tables
clusterdb -t users -t orders mydb

# All databases
clusterdb -a

# Verbose output
clusterdb -v mydb
```

### 4.4 Convenience Database/User Management Tools

**createdb** - Create a database:
```bash
# Create database
createdb newdb

# With owner and template
createdb -O owner -T template0 newdb

# With encoding and locale
createdb -E UTF8 -l en_US.UTF-8 newdb
```

**dropdb** - Remove a database:
```bash
# Drop database
dropdb olddb

# With confirmation prompt
dropdb -i olddb

# Force drop (disconnect users)
dropdb --force olddb
```

**createuser** - Create a role:
```bash
# Create user
createuser newuser

# Create superuser
createuser -s admin

# Create user with login and password prompt
createuser -l -P appuser

# Create role with specific privileges
createuser -d -r -l dbadmin
```

**dropuser** - Remove a role:
```bash
# Drop user
dropuser olduser

# With confirmation
dropuser -i olduser
```

**pg_isready** - Check server availability:
```bash
# Check local server
pg_isready

# Check remote server
pg_isready -h db.example.com -p 5432

# Use in scripts (exit code indicates status)
if pg_isready -q; then
  echo "Server ready"
fi
```

## 5. Administrative Tools

### 5.1 pg_upgrade - In-Place Major Version Upgrade

**Purpose**: `pg_upgrade` upgrades a PostgreSQL cluster to a new major version without dumping and reloading data.

**Key Source Files**:
- `src/bin/pg_upgrade/pg_upgrade.c` - Main upgrade logic
- `src/bin/pg_upgrade/check.c` - Pre-upgrade checks
- `src/bin/pg_upgrade/relfilenode.c` - File layout management
- `src/bin/pg_upgrade/tablespace.c` - Tablespace handling
- `src/bin/pg_upgrade/version.c` - Version-specific handling
- `src/bin/pg_upgrade/pg_upgrade.h` - Data structures

**Architecture**:

From source comments:
```c
/*
 * To simplify the upgrade process, we force certain system values to be
 * identical between old and new clusters:
 *
 * We control all assignments of pg_class.oid (and relfilenode) so toast
 * oids are the same between old and new clusters.  This is important
 * because toast oids are stored as toast pointers in user tables.
 *
 * We control assignments of pg_class.relfilenode because we want the
 * filenames to match between the old and new cluster.
 *
 * We control assignment of pg_type.oid, pg_enum.oid, pg_authid.oid,
 * and pg_database.oid for data consistency.
 */
```

**Upgrade Process**:

1. **Pre-flight Checks**:
   - Verify both clusters are valid
   - Check version compatibility
   - Verify no incompatible features
   - Check disk space availability

2. **Schema Migration**:
   - Dump old cluster schema with pg_dump
   - Create new cluster with initdb
   - Restore schema in new cluster
   - Preserve OIDs for critical objects

3. **Data Migration**:
   - **Link mode** (`--link`): Hard links to existing files (fast, but irreversible)
   - **Copy mode** (default): Copy all data files (safe)
   - **Clone mode** (`--clone`): Copy-on-write cloning on supported filesystems

4. **Post-upgrade**:
   - Update system catalogs
   - Generate optimizer statistics
   - Optional analyze script generation

**Main Features**:

1. **Multiple Transfer Modes**:
   - Copy (safest, slowest)
   - Link (fastest, irreversible)
   - Clone (best of both, requires filesystem support)

2. **Parallel Processing**:
   - Multiple jobs for schema dump/restore
   - Controlled via `-j` option

3. **Safety Checks**:
   - Extensive pre-upgrade validation
   - Rollback capability (except in link mode)
   - Detailed logging

**Usage Examples**:

```bash
# Check compatibility (dry run)
pg_upgrade \
  -b /usr/lib/postgresql/14/bin \
  -B /usr/lib/postgresql/15/bin \
  -d /var/lib/postgresql/14/data \
  -D /var/lib/postgresql/15/data \
  --check

# Perform upgrade with link mode
pg_upgrade \
  -b /usr/lib/postgresql/14/bin \
  -B /usr/lib/postgresql/15/bin \
  -d /var/lib/postgresql/14/data \
  -D /var/lib/postgresql/15/data \
  --link

# Upgrade with parallel jobs
pg_upgrade \
  -b /old/bin \
  -B /new/bin \
  -d /old/data \
  -D /new/data \
  -j 4

# Clone mode (requires supporting filesystem)
pg_upgrade \
  -b /old/bin \
  -B /new/bin \
  -d /old/data \
  -D /new/data \
  --clone

# With specific user and port
pg_upgrade \
  -b /old/bin -B /new/bin \
  -d /old/data -D /new/data \
  -U postgres \
  -p 5432 -P 5433
```

**Post-Upgrade Steps**:
```bash
# Run the generated analysis script
./analyze_new_cluster.sh

# Start new cluster
pg_ctl -D /new/data start

# After verification, remove old cluster
./delete_old_cluster.sh
```

### 5.2 pg_resetwal - Reset Write-Ahead Log

**Purpose**: `pg_resetwal` clears the WAL and optionally resets transaction log status. This is a last-resort recovery tool for corrupted clusters.

**Key Source Files**:
- `src/bin/pg_resetwal/pg_resetwal.c` - Complete implementation

**Architecture**:

From source comments:
```c
/*
 * The theory of operation is fairly simple:
 *  1. Read the existing pg_control (which will include the last
 *     checkpoint record).
 *  2. If pg_control is corrupt, attempt to intuit reasonable values,
 *     by scanning the old xlog if necessary.
 *  3. Modify pg_control to reflect a "shutdown" state with a checkpoint
 *     record at the start of xlog.
 *  4. Flush the existing xlog files and write a new segment with
 *     just a checkpoint record in it.  The new segment is positioned
 *     just past the end of the old xlog, so that existing LSNs in
 *     data pages will appear to be "in the past".
 */
```

**WARNING**: This tool can cause **irreversible data loss**. Only use when:
- Cluster cannot start due to corrupted WAL
- All other recovery options exhausted
- Data loss is acceptable vs. total cluster loss

**Main Features**:

1. **WAL Reset**:
   - Clear existing WAL files
   - Create new clean WAL segment
   - Reset transaction IDs

2. **Manual Control Override**:
   - Set next transaction ID (`-x`)
   - Set next OID (`-o`)
   - Set next multixact ID (`-m`)
   - Set WAL segment size

3. **Force Options**:
   - Force operation even with running server (dangerous)
   - Override safety checks

**Usage Examples**:

```bash
# Basic WAL reset (interactive confirmation)
pg_resetwal /var/lib/postgresql/data

# Non-interactive mode
pg_resetwal -f /var/lib/postgresql/data

# Dry run (show values, no changes)
pg_resetwal -n /var/lib/postgresql/data

# Set specific transaction ID
pg_resetwal -x 1000000 /var/lib/postgresql/data

# Set specific OID
pg_resetwal -o 100000 /var/lib/postgresql/data

# Set specific multixact ID
pg_resetwal -m 1000 /var/lib/postgresql/data

# Set WAL segment size (dangerous, must match data directory)
pg_resetwal --wal-segsize=32 /var/lib/postgresql/data
```

**Recovery Scenario**:
```bash
# 1. Stop server
pg_ctl -D /data stop -m immediate

# 2. Backup data directory
cp -a /data /data.backup

# 3. Attempt reset (dry run first)
pg_resetwal -n /data

# 4. Perform actual reset
pg_resetwal -f /data

# 5. Start server and check for corruption
pg_ctl -D /data start
psql -c "SELECT * FROM pg_database"

# 6. Perform consistency checks
# Use pg_amcheck or manual queries to verify data integrity
```

### 5.3 pg_rewind - Synchronize Data Directory with Another Cluster

**Purpose**: `pg_rewind` synchronizes a PostgreSQL data directory with another copy of the same cluster after they have diverged (e.g., after failover).

**Key Source Files**:
- `src/bin/pg_rewind/pg_rewind.c` - Main synchronization logic
- `src/bin/pg_rewind/filemap.c` - File change tracking
- `src/bin/pg_rewind/parsexlog.c` - WAL parsing
- `src/bin/pg_rewind/file_ops.c` - File operations
- `src/bin/pg_rewind/rewind_source.c` - Source cluster access

**Architecture**:

The utility synchronizes a data directory by:
1. Finding the common ancestor timeline
2. Parsing WAL to identify changed blocks
3. Copying only changed data from source cluster
4. Creating backup label for recovery

**Use Cases**:
- Failed primary rejoining after failover
- Standby resynchronization after timeline divergence
- Alternative to rebuilding from backup

**Main Features**:

1. **Source Options**:
   - Local data directory (`--source-pgdata`)
   - Remote server via connection (`--source-server`)

2. **Efficient Synchronization**:
   - Only copies changed blocks
   - Uses WAL parsing to identify differences
   - Much faster than full rebuild

3. **Safety Features**:
   - Dry-run mode (`--dry-run`)
   - Progress reporting
   - Comprehensive checks

**Requirements**:
- Target cluster must be shut down cleanly
- Source and target must share common history
- `wal_log_hints=on` or data checksums enabled
- Or full_page_writes=on with WAL retention

**Usage Examples**:

```bash
# Rewind from local source
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-pgdata=/mnt/primary/data

# Rewind from remote source
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server='host=primary port=5432 user=postgres'

# Dry run (show what would be done)
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server='host=primary port=5432' \
  --dry-run

# With progress reporting
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server='host=primary port=5432' \
  --progress

# Debug mode (verbose output)
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server='host=primary port=5432' \
  --debug

# With custom configuration file
pg_rewind \
  --target-pgdata=/var/lib/postgresql/data \
  --source-server='host=primary port=5432' \
  --config-file=/etc/postgresql/postgresql.conf
```

**Typical Failover Recovery Scenario**:
```bash
# 1. Old primary has failed over, new primary is active
# 2. Stop old primary
pg_ctl -D /old-primary/data stop -m fast

# 3. Rewind old primary to match new primary
pg_rewind \
  --target-pgdata=/old-primary/data \
  --source-server='host=new-primary port=5432 user=replicator'

# 4. Configure as standby
cat > /old-primary/data/standby.signal << EOF
# This file indicates standby mode
EOF

# 5. Update connection info in postgresql.auto.conf
echo "primary_conninfo = 'host=new-primary port=5432'" \
  >> /old-primary/data/postgresql.auto.conf

# 6. Start as standby
pg_ctl -D /old-primary/data start
```

## 6. Diagnostic and Verification Tools

### 6.1 pg_waldump - WAL File Decoder

**Purpose**: `pg_waldump` reads and decodes PostgreSQL Write-Ahead Log (WAL) files, displaying their contents in human-readable format.

**Key Source Files**:
- `src/bin/pg_waldump/pg_waldump.c` - Main decoder
- Shares WAL reading code with backend (`src/backend/access/transam/xlogreader.c`)

**Main Features**:

1. **WAL Inspection**:
   - Display WAL record details
   - Filter by resource manager
   - Filter by transaction ID
   - Filter by relation

2. **Statistics Mode**:
   - Aggregate statistics per record type
   - Useful for understanding WAL volume

3. **Full Page Image Extraction**:
   - Save full page images to disk
   - Useful for recovery and forensics

4. **Follow Mode**:
   - Continuous monitoring of WAL (like tail -f)
   - Real-time WAL analysis

**Usage Examples**:

```bash
# Decode specific WAL file
pg_waldump /var/lib/postgresql/data/pg_wal/000000010000000000000001

# Decode range of WAL
pg_waldump -s 0/1000000 -e 0/2000000 /data/pg_wal

# Filter by transaction ID
pg_waldump -x 1234 /data/pg_wal

# Filter by resource manager (e.g., Heap operations)
pg_waldump -r Heap /data/pg_wal

# Statistics mode
pg_waldump -z /data/pg_wal/000000010000000000000001

# Per-record statistics
pg_waldump -z --stats=record /data/pg_wal

# Extract full page images
pg_waldump --save-fullpage=/tmp/fpw /data/pg_wal

# Follow mode (continuous)
pg_waldump --follow /data/pg_wal

# Filter by relation
pg_waldump --relation=1663/16384/12345 /data/pg_wal

# Filter by block number
pg_waldump --block=100 --relation=1663/16384/12345 /data/pg_wal

# Verbose output with full details
pg_waldump -x 1234 --bkp-details /data/pg_wal
```

**Output Interpretation**:
```
rmgr: Heap        len (rec/tot):     59/    59, tx:        742, lsn: 0/0151B3A8,
  prev 0/0151B370, desc: INSERT off 3 flags 0x00, blkref #0: rel 1663/16384/16385
  blk 0

Fields:
- rmgr: Resource manager (Heap, Btree, Transaction, etc.)
- len: Record length
- tx: Transaction ID
- lsn: Log Sequence Number
- prev: Previous record LSN
- desc: Operation description
- blkref: Block reference(s)
```

### 6.2 pg_amcheck - Relation Corruption Detection

**Purpose**: `pg_amcheck` detects corruption in PostgreSQL database relations by checking heap tables and B-tree indexes.

**Key Source Files**:
- `src/bin/pg_amcheck/pg_amcheck.c` - Main checking logic
- Uses `amcheck` extension on backend: `contrib/amcheck/`

**Main Features**:

1. **Corruption Detection**:
   - Heap table corruption
   - B-tree index corruption
   - Cross-relation consistency

2. **Flexible Targeting**:
   - Entire database or cluster
   - Specific schemas, tables, indexes
   - Include/exclude patterns

3. **Parallel Checking**:
   - Multiple parallel connections
   - Faster verification of large databases

4. **Extension Management**:
   - Auto-install amcheck extension if needed
   - Configurable installation schema

**Usage Examples**:

```bash
# Check all databases
pg_amcheck --all

# Check specific database
pg_amcheck mydb

# Check all databases with progress
pg_amcheck -a --progress

# Parallel checking
pg_amcheck -a -j 4

# Check specific table
pg_amcheck -t users mydb

# Check all indexes
pg_amcheck --checkunique mydb

# Exclude specific schemas
pg_amcheck --exclude-schema=temp -a

# Install extension if missing
pg_amcheck --install-missing -a

# Verbose output
pg_amcheck -v mydb

# Heapallindexed check (thorough but slow)
pg_amcheck --heapallindexed mydb

# Skip toast tables
pg_amcheck --no-toast-check mydb
```

**Output Interpretation**:
```
# No corruption found (good):
$ pg_amcheck mydb
# (exits with status 0, no output)

# Corruption found (bad):
$ pg_amcheck mydb
heap table "public.users", block 42, offset 3: invalid tuple length
btree index "public.users_pkey": block 10 is not properly initialized
# (exits with non-zero status)
```

### 6.3 pg_controldata - Display Control File Information

**Purpose**: Displays the contents of the `pg_control` file, which contains critical cluster state information.

**Usage**:
```bash
# Display control information
pg_controldata /var/lib/postgresql/data

# Example output:
pg_control version number:            1300
Catalog version number:               202107181
Database system identifier:           7012345678901234567
Database cluster state:               in production
pg_control last modified:             Mon Nov 18 10:30:45 2024
Latest checkpoint location:           0/1A2B3C4D
Latest checkpoint's REDO location:    0/1A2B3C00
Latest checkpoint's TimeLineID:       1
Latest checkpoint's NextXID:          0:1234567
Latest checkpoint's NextOID:          24576
```

### 6.4 pg_checksums - Enable/Disable/Verify Data Checksums

**Purpose**: Manage page-level checksums for data integrity verification.

**Usage**:
```bash
# Enable checksums (cluster must be offline)
pg_checksums --enable -D /var/lib/postgresql/data

# Disable checksums
pg_checksums --disable -D /var/lib/postgresql/data

# Verify checksums
pg_checksums --check -D /var/lib/postgresql/data

# Verify with progress
pg_checksums --check --progress -D /var/lib/postgresql/data
```

### 6.5 Other Diagnostic Tools

**pg_test_fsync** - Test filesystem sync performance:
```bash
# Benchmark fsync methods
pg_test_fsync

# Output shows performance of different sync methods
# Useful for optimizing wal_sync_method
```

**pg_test_timing** - Test timing overhead:
```bash
# Measure timing call overhead
pg_test_timing

# Useful for understanding EXPLAIN ANALYZE accuracy
```

**pg_archivecleanup** - Clean up WAL archives:
```bash
# Remove old WAL files before specified segment
pg_archivecleanup /archive/wal 000000010000000000000010

# Dry run
pg_archivecleanup -n /archive/wal 000000010000000000000010
```

**pg_config** - Display PostgreSQL build configuration:
```bash
# Show all configuration
pg_config

# Show specific value
pg_config --includedir
pg_config --libdir
pg_config --configure
```

## 7. Benchmarking - pgbench

### 7.1 Overview

**Purpose**: `pgbench` is a benchmarking tool for PostgreSQL, designed to run predefined or custom workloads and measure database performance.

**Key Source Files**:
- `src/bin/pgbench/pgbench.c` - Main benchmarking engine
- `src/bin/pgbench/pgbench.h` - Data structures
- `src/bin/pgbench/exprparse.y` - Expression parser for scripts

**Architecture**:

pgbench operates in two modes:
1. **Initialization mode** (`-i`): Creates and populates benchmark tables
2. **Benchmarking mode** (default): Runs transactions and measures performance

**Benchmark Tables** (TPC-B inspired):
```sql
pgbench_accounts (100,000 rows per scale)
pgbench_branches (1 row per scale)
pgbench_tellers  (10 rows per scale)
pgbench_history  (append-only transaction log)
```

### 7.2 Main Features

1. **Built-in Benchmarks**:
   - TPC-B-like workload (default)
   - Simple update workload (`-S` for SELECT only)
   - Custom SQL scripts (`-f` option)

2. **Workload Control**:
   - Number of clients (`-c`)
   - Number of threads (`-j`)
   - Number of transactions (`-t`) or duration (`-T`)
   - Connection mode (new connection per transaction)

3. **Advanced Features**:
   - Rate limiting (`--rate`)
   - Latency reporting (`--latency`)
   - Progress reporting (`--progress`)
   - Prepared statements
   - Pipeline mode (protocol-level pipelining)
   - Partitioned tables support

4. **Custom Scripts**:
   - Variable substitution
   - Random number generation
   - Conditional execution
   - Meta-commands for control flow

5. **Statistical Reporting**:
   - Transactions per second (TPS)
   - Latency (average, stddev)
   - Percentile latencies (median, 90th, 95th, 99th)
   - Per-statement latencies

### 7.3 Usage Examples

**Basic Benchmarking**:

```bash
# Initialize with scale factor 10 (1M rows in pgbench_accounts)
pgbench -i -s 10 mydb

# Run default TPC-B benchmark (10 clients, 1000 transactions each)
pgbench -c 10 -t 1000 mydb

# Run for 60 seconds instead of fixed transactions
pgbench -c 10 -T 60 mydb

# Select-only workload
pgbench -c 10 -T 60 -S mydb

# With progress reporting every 5 seconds
pgbench -c 10 -T 60 --progress=5 mydb

# Multiple threads (for multicore systems)
pgbench -c 20 -j 4 -T 60 mydb
```

**Advanced Options**:

```bash
# Detailed latency statistics
pgbench -c 10 -T 60 --latency mydb

# With rate limiting (max 1000 TPS)
pgbench -c 10 -T 60 --rate=1000 mydb

# Latency threshold (report slow transactions > 100ms)
pgbench -c 10 -T 60 --latency-limit=100 mydb

# Per-statement latencies
pgbench -c 10 -T 60 --report-per-command mydb

# Connection overhead test (new connection per transaction)
pgbench -c 10 -t 100 -C mydb

# Use prepared statements
pgbench -c 10 -T 60 -M prepared mydb

# Protocol-level pipelining
pgbench -c 10 -T 60 -M pipeline mydb
```

**Custom Scripts**:

```bash
# Create custom script file (bench.sql)
cat > bench.sql << 'EOF'
\set aid random(1, 100000)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
EOF

# Run custom script
pgbench -c 10 -T 60 -f bench.sql mydb

# Multiple scripts with weights
pgbench -c 10 -T 60 -f read.sql@5 -f write.sql@1 mydb
```

**Custom Script Features**:

```sql
-- Variable assignment
\set nbranches 10
\set ntellers 100
\set naccounts 100000

-- Random values
\set aid random(1, :naccounts)
\set delta random(-5000, 5000)

-- Conditional execution
\if :scale >= 100
  SELECT * FROM large_table WHERE id = :aid;
\else
  SELECT * FROM small_table WHERE id = :aid;
\endif

-- Sleep (microseconds)
\sleep 1000 us

-- Set variable from query result
\setshell hostname hostname
```

**Initialization Options**:

```bash
# Initialize with foreign keys
pgbench -i --foreign-keys mydb

# Initialize with tablespaces
pgbench -i --tablespace=fast_ssd mydb
pgbench -i --index-tablespace=fast_ssd mydb

# Initialize partitioned tables (v12+)
pgbench -i --partitions=10 mydb

# Initialize without vacuuming
pgbench -i --no-vacuum mydb

# Initialize only specific tables
pgbench -i --init-steps=dtv mydb  # d=drop, t=create tables, v=vacuum
```

### 7.4 Output Interpretation

**Standard Output**:
```
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 10
number of threads: 1
number of transactions per client: 1000
number of transactions actually processed: 10000/10000
latency average = 15.844 ms
tps = 631.234567 (including connections establishing)
tps = 631.456789 (excluding connections establishing)
```

**With Latency Details** (`--latency`):
```
...
latency average = 15.844 ms
latency stddev = 8.234 ms
tps = 631.234567 (including connections establishing)
tps = 631.456789 (excluding connections establishing)
```

**With Progress** (`--progress=5`):
```
progress: 5.0 s, 645.2 tps, lat 15.484 ms stddev 7.823
progress: 10.0 s, 638.4 tps, lat 15.657 ms stddev 8.142
progress: 15.0 s, 651.8 tps, lat 15.342 ms stddev 7.654
...
```

**Percentile Latencies**:
```
latency average = 15.844 ms
latency stddev = 8.234 ms
initial connection time = 12.345 ms
tps = 631.234567 (without initial connection time)

statement latencies in milliseconds:
         0.002  \set aid random(1, 100000 * :scale)
         0.001  \set bid random(1, 1 * :scale)
         0.001  \set tid random(1, 10 * :scale)
         0.001  \set delta random(-5000, 5000)
         0.153  BEGIN;
         0.245  UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
         0.187  SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
         0.231  UPDATE pgbench_tellers SET tbalance = tbalance + :delta WHERE tid = :tid;
         0.219  UPDATE pgbench_branches SET bbalance = bbalance + :delta WHERE bid = :bid;
         0.198  INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);
        14.607  END;
```

### 7.5 Backend Integration

pgbench uses standard libpq for all database operations:
- Can use simple, extended, or prepared statement protocols
- Supports pipeline mode (PostgreSQL 14+)
- Creates standard connection per client/thread
- No special backend support required

**Performance Considerations**:
- Scale factor determines dataset size (scale 100 = 10M accounts ≈ 1.5GB)
- More clients than CPU cores can show contention
- Thread count should typically match CPU cores
- Rate limiting useful for steady-state testing
- Connection pooling (external) recommended for high client counts

## 8. Utility Program Infrastructure

### 8.1 Shared Components

All PostgreSQL utilities share common infrastructure located in:

**Frontend Utilities Library** (`src/fe_utils/`):
- `option_utils.c` - Command-line option parsing
- `string_utils.c` - String manipulation
- `print.c` - Result formatting (used by psql)
- `connect.c` - Connection handling
- `parallel_slot.c` - Parallel execution framework
- `simple_list.c` - Simple list data structure
- `query_utils.c` - Query execution helpers

**Common Code** (`src/common/`):
- `logging.c` - Unified logging framework
- `file_utils.c` - File operations
- `controldata_utils.c` - pg_control reading
- `fe_memutils.c` - Memory allocation wrappers
- `username.c` - Username detection
- `restricted_token.c` - Windows security

**LibPQ Integration**:
All utilities use libpq (`src/interfaces/libpq/`) for server communication:
- Connection management
- Query execution
- Result processing
- Error handling
- Protocol-level features (COPY, prepared statements, pipeline mode)

### 8.2 Connection Handling Patterns

**Standard Connection Flow**:
```c
// Typical connection pattern
PGconn *conn = PQconnectdb(connstring);
if (PQstatus(conn) != CONNECTION_OK) {
    fprintf(stderr, "Connection failed: %s", PQerrorMessage(conn));
    exit(1);
}

// Execute query
PGresult *res = PQexec(conn, "SELECT version()");
if (PQresultStatus(res) != PGRES_TUPLES_OK) {
    // Error handling
}

// Process results
// ...

PQclear(res);
PQfinish(conn);
```

**Connection String Formats**:
```bash
# Keyword/value format
"host=localhost port=5432 dbname=mydb user=postgres"

# URI format
"postgresql://postgres@localhost:5432/mydb"

# With multiple hosts (failover)
"host=primary,standby port=5432,5432 dbname=mydb"
```

### 8.3 Logging Framework

All modern utilities use the unified logging framework:

```c
#include "common/logging.h"

// Set program name
pg_logging_init(argv[0]);

// Log messages at different levels
pg_log_error("Connection failed");
pg_log_warning("Table not found, skipping");
pg_log_info("Processing 1000 tables");
pg_log_debug("Query: %s", query);

// Fatal error (logs and exits)
pg_fatal("Cannot continue: %s", reason);
```

**Log Levels**:
- `PG_LOG_ERROR` - Errors (non-fatal)
- `PG_LOG_WARNING` - Warnings
- `PG_LOG_INFO` - Informational messages
- `PG_LOG_DEBUG` - Debug output
- `PG_LOG_FATAL` - Fatal errors (exit program)

### 8.4 Error Handling Conventions

**Exit Codes**:
- `0` - Success
- `1` - General error
- `2` - Connection error
- `3` - Script error (psql)

**Error Reporting**:
All utilities report errors to stderr and provide meaningful messages including:
- Context of the operation
- Specific error details
- Suggested remediation when possible

## 9. Platform Considerations

### 9.1 Unix/Linux

**Installation Paths**:
- Binaries: `/usr/bin/` or `/usr/local/pgsql/bin/`
- Libraries: `/usr/lib/` or `/usr/local/pgsql/lib/`
- Data: Typically `/var/lib/postgresql/` or custom location

**Signal Handling**:
- `SIGTERM` - Fast shutdown
- `SIGINT` - Fast shutdown (Ctrl+C)
- `SIGQUIT` - Immediate shutdown
- `SIGHUP` - Reload configuration

### 9.2 Windows

**Service Management**:
```cmd
# Register as Windows service
pg_ctl register -N "PostgreSQL" -D "C:\data"

# Unregister service
pg_ctl unregister -N "PostgreSQL"
```

**Path Differences**:
- Binaries: `C:\Program Files\PostgreSQL\15\bin\`
- Data: `C:\Program Files\PostgreSQL\15\data\`
- Configuration: Same directory as Unix but backslashes

**Authentication**:
- Supports Windows SSPI authentication
- Can run as Windows service account
- Integrated Windows authentication available

## 10. Best Practices and Guidelines

### 10.1 Backup Strategies

**Logical Backups (pg_dump)**:
- **Use for**: Individual databases, partial backups, cross-version compatibility
- **Pros**: Portable, selective, human-readable (plain format)
- **Cons**: Slower, larger, requires restore time

**Physical Backups (pg_basebackup)**:
- **Use for**: Entire clusters, PITR, standby setup
- **Pros**: Fast, exact copy, streaming replication compatible
- **Cons**: Not portable, version-specific, all-or-nothing

**Recommended Approach**:
```bash
# Daily basebackup for PITR
pg_basebackup -D /backup/$(date +%Y%m%d) -Ft -z -X stream

# Weekly logical backup for portability
pg_dump -Fc mydb > /backup/weekly/mydb-$(date +%Y%m%d).dump

# Keep WAL archives for point-in-time recovery
# (configure archive_command in postgresql.conf)
```

### 10.2 Maintenance Schedules

**Regular Maintenance**:
```bash
# Daily: Vacuum and analyze
vacuumdb -z -a

# Weekly: More aggressive vacuum
vacuumdb --analyze-in-stages -a

# Monthly: Reindex critical indexes
reindexdb --concurrently -t critical_table mydb

# As needed: Cluster frequently accessed tables
clusterdb -t hot_table mydb
```

**Monitoring**:
```bash
# Check server status
pg_isready && echo "Server ready" || echo "Server down"

# Monitor WAL usage
pg_waldump --stats=record /data/pg_wal/latest

# Check for corruption
pg_amcheck -a --progress
```

### 10.3 Performance Testing

**pgbench Best Practices**:
```bash
# 1. Size database appropriately (scale ≈ 10× RAM for realistic test)
pgbench -i -s 1000 testdb

# 2. Warm up database
pgbench -c 10 -T 60 -S testdb

# 3. Run actual benchmark with latency tracking
pgbench -c 50 -j 8 -T 600 --progress=10 --latency testdb

# 4. Test different scenarios
pgbench -c 50 -T 300 -S testdb          # Read-heavy
pgbench -c 50 -T 300 testdb             # Write-heavy
pgbench -c 50 -T 300 -f custom.sql testdb  # Custom workload
```

### 10.4 Security Considerations

**Authentication**:
```bash
# Always use strong authentication in pg_hba.conf
# Prefer scram-sha-256 over md5
initdb --auth-host=scram-sha-256 --auth-local=peer -D /data

# Use connection service files to avoid passwords in scripts
# ~/.pg_service.conf:
# [production]
# host=db.example.com
# dbname=mydb
# user=admin

# Then: psql service=production
```

**File Permissions**:
- Data directory must be owned by postgres user
- Mode 0700 (read/write/execute for owner only)
- Utilities enforce these restrictions

**Network Security**:
```bash
# Use SSL for remote connections
psql "sslmode=require host=remote dbname=mydb"

# Verify server certificate
psql "sslmode=verify-full sslrootcert=/path/to/ca.crt host=remote dbname=mydb"
```

## 11. Troubleshooting Common Issues

### 11.1 Connection Problems

**Issue**: Cannot connect to server
```bash
# Check if server is running
pg_isready -h localhost -p 5432

# Verify pg_hba.conf allows connection
# Check PostgreSQL logs for authentication errors

# Test with different authentication
psql -h localhost -U postgres postgres
```

**Issue**: Too many connections
```bash
# Check current connections
psql -c "SELECT count(*) FROM pg_stat_activity"

# Adjust max_connections in postgresql.conf
# Use connection pooling (pgBouncer, pgpool)
```

### 11.2 Backup/Restore Issues

**Issue**: pg_dump fails with "cache lookup failed"
```bash
# Someone performed DDL during dump
# Use --no-synchronized-snapshots (less safe) or
# Ensure no concurrent DDL during backup window
```

**Issue**: pg_restore out of memory
```bash
# Restore in smaller chunks
pg_restore -l backup.dump > toc.list
# Edit toc.list to select subset
pg_restore -L toc.list -d mydb backup.dump
```

### 11.3 Performance Issues

**Issue**: pgbench shows low TPS
```bash
# Check for I/O bottlenecks
pg_test_fsync

# Tune PostgreSQL configuration
# - shared_buffers (25% of RAM)
# - effective_cache_size (50-75% of RAM)
# - work_mem (RAM / max_connections / 2)

# Monitor with pg_stat_statements
psql -c "CREATE EXTENSION pg_stat_statements"
```

**Issue**: Vacuum/analyze taking too long
```bash
# Use parallel workers
vacuumdb -j 4 mydb

# Check for long-running transactions (prevents vacuum)
psql -c "SELECT pid, state, age(clock_timestamp(), query_start)
         FROM pg_stat_activity
         WHERE state != 'idle'
         ORDER BY age DESC"
```

## 12. Future Directions

### 12.1 Recent Enhancements

**PostgreSQL 14**:
- Pipeline mode in libpq (supported by psql, pgbench)
- Compression in pg_basebackup (`--compress=`)
- pg_amcheck utility introduced

**PostgreSQL 15**:
- Server-side compression for pg_basebackup
- ICU collation improvements in initdb
- Enhanced pg_waldump filtering

**PostgreSQL 16**:
- Logical replication slot support in pg_basebackup
- Incremental backup support
- Enhanced pg_stat_statements in psql

### 12.2 Ongoing Development

**Active Areas**:
- Incremental backup and restore
- Better parallel processing across utilities
- Enhanced diagnostic capabilities
- Improved progress reporting
- Cloud-native features

## Conclusion

PostgreSQL's utility programs form a comprehensive ecosystem for database administration, maintenance, and operations. From the powerful psql interactive terminal to specialized tools like pg_waldump for WAL analysis, each utility is designed to excel at specific tasks while sharing common infrastructure.

Understanding these utilities is essential for:
- **Database Administrators**: Daily operations, backup/recovery, troubleshooting
- **Developers**: Testing, benchmarking, database setup
- **DevOps Engineers**: Automation, monitoring, deployment
- **Database Reliability Engineers**: Disaster recovery, performance optimization

The utilities follow PostgreSQL's philosophy of providing simple, composable tools that do one thing well. They integrate seamlessly with the backend through libpq and the PostgreSQL protocol, while remaining independent enough to version and evolve separately.

Key takeaways:
1. **Choose the right tool**: Logical vs physical backups, pg_upgrade vs dump/restore
2. **Understand the trade-offs**: Speed vs safety, convenience vs control
3. **Leverage parallelism**: Most modern utilities support parallel operations
4. **Practice safe operations**: Use dry-run modes, maintain backups, test in non-production
5. **Monitor and verify**: Use diagnostic tools regularly, verify backups, check for corruption

The PostgreSQL utility suite continues to evolve with each release, adding new capabilities while maintaining backward compatibility and the simplicity that makes them powerful tools for database professionals.

## References

**Source Code**:
- `src/bin/` - All utility programs
- `src/fe_utils/` - Frontend utilities library
- `src/common/` - Common code
- `src/interfaces/libpq/` - PostgreSQL client library

**Documentation**:
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Client Applications reference
- Server Administration guide

**Related Backend Components**:
- `src/backend/replication/basebackup.c` - pg_basebackup backend
- `src/backend/commands/vacuum.c` - VACUUM implementation
- `src/backend/postmaster/pgarch.c` - WAL archiving
- `src/backend/access/transam/xlog.c` - WAL management
