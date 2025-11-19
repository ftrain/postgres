# Chapter 1: Storage Layer Architecture

## Table of Contents
- [Introduction](#introduction)
- [Page Structure](#page-structure)
- [Buffer Manager](#buffer-manager)
- [Heap Access Method](#heap-access-method)
- [Write-Ahead Logging](#write-ahead-logging)
- [Multi-Version Concurrency Control](#multi-version-concurrency-control)
- [Index Access Methods](#index-access-methods)
- [Free Space Map](#free-space-map)
- [Visibility Map](#visibility-map)
- [TOAST](#toast)
- [Conclusion](#conclusion)

## Introduction

The storage layer is the foundation of PostgreSQL's architecture, responsible for organizing data on disk, managing memory buffers, ensuring crash recovery, and providing efficient data access. Unlike many database systems that rely on proprietary storage engines, PostgreSQL implements a sophisticated storage layer that seamlessly integrates with its query processing, transaction management, and concurrency control subsystems.

This chapter explores the complete storage layer architecture, from the low-level page format to high-level abstractions like access methods. Understanding these components is essential for database administrators seeking to optimize performance, developers building extensions, and anyone interested in the inner workings of a modern relational database system.

### Key Components Overview

The PostgreSQL storage layer consists of several interconnected components:

- **Page Structure**: The fundamental 8KB unit of storage organization
- **Buffer Manager**: Memory caching layer between disk and query execution
- **Heap Access Method**: The default table storage mechanism
- **Write-Ahead Logging (WAL)**: Crash recovery and replication foundation
- **MVCC**: Multi-version concurrency control for transaction isolation
- **Index Access Methods**: Six specialized index types for different query patterns
- **Free Space Map**: Efficient space management for INSERT operations
- **Visibility Map**: Optimization for VACUUM and index-only scans
- **TOAST**: Storage system for large attribute values

### Design Philosophy

PostgreSQL's storage layer embodies several key design principles:

1. **Reliability First**: All data modifications are protected by WAL
2. **Extensibility**: The access method API allows new storage engines
3. **Performance**: Multi-level caching and efficient data structures
4. **Standards Compliance**: Full ACID transaction support
5. **Flexibility**: Multiple index types for diverse workloads

## Page Structure

### Overview

The page is the fundamental unit of storage in PostgreSQL. All data files—tables, indexes, and internal structures—are organized as sequences of fixed-size pages. The standard page size is 8KB (8192 bytes), though it can be configured at compile time to 1, 2, 4, 8, 16, or 32 KB.

The page structure implements a **slotted page design**, which provides flexibility for variable-length tuples while maintaining efficient space utilization. This design is defined in `src/include/storage/bufpage.h` and implemented throughout the storage layer.

### Page Layout

Every page follows a consistent layout:

```
+----------------+ ← Page Start (offset 0)
| Page Header    | 24 bytes
+----------------+
| Item Pointers  | Array growing forward
|      ...       |
+----------------+ ← pd_lower
|                |
| Free Space     |
|                |
+----------------+ ← pd_upper
| Tuple Data     | Growing backward
|      ...       |
+----------------+
| Special Space  | Index-specific data
+----------------+ ← Page End (offset 8192)
```

**Key characteristics:**
- Fixed-size header at the beginning
- Item pointer array grows forward from the header
- Tuple data grows backward from the end
- Free space in the middle allows both areas to grow
- Optional special space at the end for index metadata

### Page Header Structure

The page header (`PageHeaderData`) contains essential metadata:

```c
typedef struct PageHeaderData
{
    PageXLogRecPtr pd_lsn;      /* LSN: next byte after last byte of WAL
                                 * record for last change to this page */
    uint16      pd_checksum;     /* checksum */
    uint16      pd_flags;        /* flag bits */
    LocationIndex pd_lower;      /* offset to start of free space */
    LocationIndex pd_upper;      /* offset to end of free space */
    LocationIndex pd_special;    /* offset to start of special space */
    uint16      pd_pagesize_version;
    TransactionId pd_prune_xid;  /* oldest prunable XID, or zero if none */
    ItemIdData  pd_linp[FLEXIBLE_ARRAY_MEMBER]; /* line pointer array */
} PageHeaderData;
```

**Field descriptions:**

- **pd_lsn**: Log Sequence Number indicating the last WAL record that modified this page. Critical for crash recovery and replication.
- **pd_checksum**: Data integrity verification (when enabled with `--enable-checksum`)
- **pd_flags**: Bitmap of page attributes (has free space, all tuples visible, etc.)
- **pd_lower**: Offset to the start of free space (end of item pointer array)
- **pd_upper**: Offset to the end of free space (start of tuple data)
- **pd_special**: Offset to special space (0 for heap pages, non-zero for indexes)
- **pd_pagesize_version**: Page size and layout version
- **pd_prune_xid**: Optimization for HOT (Heap-Only Tuple) pruning
- **pd_linp**: Beginning of the item pointer array

### Item Pointers

Item pointers (also called line pointers) form an indirection layer between tuple identifiers and physical tuple locations. Each item pointer is 4 bytes:

```c
typedef struct ItemIdData
{
    unsigned    lp_off:15,      /* offset to tuple (from start of page) */
                lp_flags:2,     /* state of line pointer */
                lp_len:15;      /* byte length of tuple */
} ItemIdData;
```

**Item pointer states** (lp_flags):
- **LP_UNUSED** (0): Item pointer is available for reuse
- **LP_NORMAL** (1): Points to a normal tuple
- **LP_REDIRECT** (2): Redirects to another item pointer (HOT chains)
- **LP_DEAD** (3): Tuple is dead but space not yet reclaimed

**Why use indirection?**

The item pointer array provides critical benefits:

1. **Stable Tuple Identifiers**: External references (indexes, CTID columns) point to item numbers, not physical offsets
2. **Defragmentation**: Tuples can be moved within a page without updating indexes
3. **HOT Updates**: Tuple chains can be maintained through redirects
4. **Space Reclamation**: Dead tuples can be compacted without breaking references

### Tuple Structure

Heap tuples have a header followed by null bitmap and attribute data:

```c
typedef struct HeapTupleHeaderData
{
    union
    {
        HeapTupleFields t_heap;
        DatumTupleFields t_datum;
    } t_choice;

    ItemPointerData t_ctid;     /* current TID or next TID in chain */
    uint16      t_infomask2;    /* attribute count and flags */
    uint16      t_infomask;     /* various flag bits */
    uint8       t_hoff;         /* offset to user data */

    /* Followed by null bitmap and attribute data */
} HeapTupleHeaderData;
```

**Critical fields:**

- **t_xmin**: Transaction ID that inserted this tuple
- **t_xmax**: Transaction ID that deleted or updated this tuple (0 if current)
- **t_ctid**: Current tuple ID (self-reference) or pointer to newer version
- **t_infomask**: Flags indicating tuple properties (see MVCC section)
- **t_hoff**: Header offset where actual column data begins

### Page Organization Examples

**Example 1: Simple heap page with three tuples**

```
Offset | Content
-------+--------------------------------------------------
0      | Page header (24 bytes)
24     | Item 1 pointer → offset=8168, len=24
28     | Item 2 pointer → offset=8144, len=24
32     | Item 3 pointer → offset=8120, len=24
36     | [Free Space: 8084 bytes]
8120   | Tuple 3 data (24 bytes)
8144   | Tuple 2 data (24 bytes)
8168   | Tuple 3 data (24 bytes)
```

**Example 2: Page after DELETE (before VACUUM)**

```
Offset | Content
-------+--------------------------------------------------
0      | Page header
24     | Item 1 pointer → LP_NORMAL, offset=8168, len=24
28     | Item 2 pointer → LP_DEAD (marked for cleanup)
32     | Item 3 pointer → LP_NORMAL, offset=8120, len=24
36     | [Free Space includes dead tuple space]
8120   | Tuple 3 data (24 bytes)
8144   | Dead tuple data (24 bytes, reclaimable)
8168   | Tuple 1 data (24 bytes)
```

### Page-Level Operations

Key operations defined in `src/backend/storage/page/bufpage.c`:

**PageAddItem**: Adds a new item to a page
```c
OffsetNumber PageAddItem(Page page, Item item, Size size,
                         OffsetNumber offsetNumber, bool overwrite,
                         bool is_heap);
```

**PageRepairFragmentation**: Compacts tuples to reclaim free space
```c
void PageRepairFragmentation(Page page);
```

**PageGetFreeSpace**: Returns available free space
```c
Size PageGetFreeSpace(Page page);
```

### Page Types

PostgreSQL uses different page layouts for different purposes:

1. **Heap Pages**: Standard table data (no special space)
2. **B-tree Pages**: Special space contains left/right sibling links, level
3. **Hash Pages**: Special space contains bucket information
4. **GiST Pages**: Special space contains flags and tree navigation data
5. **GIN Pages**: Special space varies by page type (entry tree vs posting tree)
6. **SP-GiST Pages**: Special space contains node type and traversal data

### Page File Organization

Pages are organized in files within the PostgreSQL data directory:

```
$PGDATA/base/<database_oid>/<relation_oid>
$PGDATA/base/<database_oid>/<relation_oid>.1  (if > 1GB)
$PGDATA/base/<database_oid>/<relation_oid>_fsm  (free space map)
$PGDATA/base/<database_oid>/<relation_oid>_vm   (visibility map)
```

Each file is divided into 1GB segments to accommodate filesystems with size limits. A table's first segment has no suffix, subsequent segments are numbered `.1`, `.2`, etc.

**Block numbering**: Pages are numbered sequentially starting from 0. A block number combined with the relation OID uniquely identifies a page within a database.

### Alignment and Padding

PostgreSQL enforces strict alignment requirements:

- **MAXALIGN**: Typically 8 bytes on 64-bit systems
- Tuple data is aligned to MAXALIGN boundaries
- Individual attributes aligned according to their type (2, 4, or 8 bytes)
- Padding bytes inserted to maintain alignment

This alignment is critical for:
- CPU performance (aligned memory access)
- Portability across architectures
- Preventing unaligned access faults on strict architectures

### Performance Implications

The slotted page design has important performance characteristics:

**Advantages:**
- Efficient use of space with variable-length tuples
- Fast tuple insertion (append to end, add pointer)
- Stable tuple identifiers via indirection
- Support for in-page tuple chains (HOT)

**Trade-offs:**
- Item pointer overhead (4 bytes per tuple)
- Fragmentation can waste space
- Page-level locking during modifications
- Fixed page size limits maximum tuple size

## Buffer Manager

### Overview

The buffer manager is PostgreSQL's memory caching layer, mediating all access between disk storage and query execution. Located in `src/backend/storage/buffer/bufmgr.c` (7,468 lines), it implements a sophisticated shared buffer pool that dramatically improves performance by keeping frequently accessed pages in RAM.

Every page read or modification flows through the buffer manager, making it one of the most performance-critical subsystems in PostgreSQL. The buffer manager handles page caching, replacement policies, I/O scheduling, and coordination with the WAL system.

### Architecture

The buffer manager architecture consists of several key components:

```
+------------------+
| Query Execution  |
+------------------+
         ↓
+------------------+
| Buffer Manager   |
| - Buffer Pool    |
| - Buffer Table   |
| - Buffer Locks   |
| - Replacement    |
+------------------+
         ↓
+------------------+
| Storage Manager  |
| - File I/O       |
+------------------+
         ↓
+------------------+
| Operating System |
| - File Cache     |
+------------------+
```

### Buffer Pool Structure

The buffer pool (`shared_buffers` configuration parameter) is a large array of buffer descriptors, each managing one 8KB page:

```c
typedef struct BufferDesc
{
    BufferTag   tag;            /* ID of page contained in buffer */
    int         buf_id;         /* buffer's index in BufferDescriptors */

    pg_atomic_uint32 state;     /* atomic state flags and refcount */
    int         wait_backend_pid; /* backend waiting for this buffer */

    int         freeNext;       /* link in freelist chain */

    LWLock      content_lock;   /* to lock access to buffer contents */
} BufferDesc;
```

**BufferTag** uniquely identifies a page:

```c
typedef struct BufferTag
{
    RelFileNode rnode;          /* relation file identification */
    ForkNumber  forkNum;        /* fork number (main, FSM, VM, init) */
    BlockNumber blockNum;       /* block number within the fork */
} BufferTag;
```

**State Flags** (stored in atomic state field):
- **BM_DIRTY**: Page has been modified since read from disk
- **BM_VALID**: Buffer contains valid data
- **BM_TAG_VALID**: Buffer tag is valid
- **BM_IO_IN_PROGRESS**: I/O is in progress for this buffer
- **BM_IO_ERROR**: I/O error occurred
- **BM_JUST_DIRTIED**: Recently dirtied (for WAL optimization)
- **BM_PERMANENT**: Page from permanent relation
- Plus reference count in upper bits

### Buffer Table (Hash Table)

The buffer table is a shared hash table mapping BufferTags to buffer descriptors:

```c
/* Hash table for buffer lookup */
static HTAB *SharedBufHash;
```

**Key operations:**

1. **BufTableLookup**: Find buffer descriptor for a given page
2. **BufTableInsert**: Add new page to buffer table
3. **BufTableDelete**: Remove page from buffer table

The hash table uses **dynahash** (PostgreSQL's extensible hash table implementation) with partitioned locking to minimize contention:

```c
#define NUM_BUFFER_PARTITIONS  128
```

Each partition has its own lock, allowing concurrent lookups in different partitions.

### Buffer Access Protocol

Reading a page follows a strict protocol:

```c
Buffer ReadBuffer(Relation reln, BlockNumber blockNum);
```

**Step-by-step process:**

1. **Compute buffer tag** from relation and block number
2. **Acquire partition lock** for buffer table lookup
3. **Search buffer table** for existing buffer:
   - **If found (cache hit)**:
     - Increment reference count
     - Release partition lock
     - Acquire content lock if needed
     - Return buffer
   - **If not found (cache miss)**:
     - Select victim buffer using clock sweep algorithm
     - If victim is dirty, write to disk (possibly via WAL)
     - Replace victim's tag with new tag
     - Release partition lock
     - Read page from disk
     - Mark buffer valid
     - Return buffer

4. **Access page data** through buffer
5. **Release buffer** (decrement reference count)

### Buffer Replacement: Clock Sweep Algorithm

PostgreSQL uses a variant of the **clock sweep algorithm** for buffer replacement:

```c
/*
 * StrategyGetBuffer - get a buffer from the freelist or evict one
 */
BufferDesc *StrategyGetBuffer(BufferAccessStrategy strategy,
                              uint32 *buf_state);
```

**Algorithm overview:**

The buffer manager maintains a circular list (clock) of all buffers with a "clock hand" pointer. Each buffer has a usage count (0-5):

```
      ↓ Clock Hand
[Buf0] [Buf1] [Buf2] [Buf3] ... [BufN]
 uc=2   uc=5   uc=0   uc=3      uc=1
```

**Replacement process:**

1. Start at current clock hand position
2. Examine buffer at clock hand:
   - If usage count = 0 and not pinned: **select as victim**
   - If usage count > 0: **decrement usage count, advance clock hand**
   - If pinned: **advance clock hand**
3. Repeat until victim found

**Usage count incrementation:**
- Incremented on buffer access (up to maximum of 5)
- Decremented by clock sweep
- Provides a form of LRU approximation with low overhead

### Buffer Access Strategies

For certain operations, PostgreSQL uses specialized **buffer access strategies** to avoid polluting the buffer cache:

```c
typedef enum BufferAccessStrategyType
{
    BAS_NORMAL,         /* Normal random access */
    BAS_BULKREAD,       /* Large sequential scan */
    BAS_BULKWRITE,      /* COPY or bulk INSERT */
    BAS_VACUUM          /* VACUUM operation */
} BufferAccessStrategyType;
```

**BAS_BULKREAD** (sequential scans):
- Uses a small ring buffer (256 KB by default)
- Prevents large table scans from evicting useful cached pages
- Cycles through ring buffer, reusing same buffers

**BAS_VACUUM**:
- Uses 256 KB ring buffer
- Isolates VACUUM I/O from normal queries

**BAS_BULKWRITE**:
- Uses 16 MB ring buffer
- For COPY and CREATE TABLE AS operations

### Buffer Pinning and Locking

Buffers use a two-level locking mechanism:

**1. Reference Count (Pin Count)**
```c
Buffer buf = ReadBuffer(rel, blocknum);
/* Buffer is now "pinned" (reference count > 0) */
/* Prevents buffer from being evicted */
ReleaseBuffer(buf);  /* Decrement reference count */
```

**2. Content Locks**
```c
LockBuffer(buf, BUFFER_LOCK_SHARE);     /* Shared lock for reading */
LockBuffer(buf, BUFFER_LOCK_EXCLUSIVE); /* Exclusive lock for writing */
LockBuffer(buf, BUFFER_LOCK_UNLOCK);    /* Release lock */
```

**Why two levels?**

- **Reference count**: Ensures buffer isn't evicted while in use
- **Content lock**: Ensures consistent reads/writes of page data
- Can hold pin without lock (e.g., while waiting for another resource)
- Multiple backends can pin same buffer concurrently

### Write-Ahead Logging Integration

Buffer manager coordinates closely with WAL:

**Rule: WAL Before Data (WAL Protocol)**
```
Before writing a dirty buffer to disk:
1. Ensure all WAL records up to buffer's pd_lsn are flushed
2. This guarantees recovery can replay necessary changes
```

Implementation in `FlushBuffer`:

```c
static void FlushBuffer(BufferDesc *buf, SMgrRelation reln)
{
    XLogRecPtr  recptr;

    /* Get buffer's LSN */
    recptr = BufferGetLSN(buf);

    /* Ensure WAL is flushed up to this LSN */
    XLogFlush(recptr);

    /* Now safe to write buffer to disk */
    smgrwrite(reln, forkNum, blockNum, bufToWrite, false);
}
```

### Background Writer and Checkpointer

Two background processes help manage dirty buffers:

**Background Writer** (`bgwriter`):
- Continuously scans buffer pool
- Writes dirty buffers to reduce checkpoint I/O spike
- Uses clock sweep to find dirty buffers with low usage count
- Configured via `bgwriter_delay`, `bgwriter_lru_maxpages`, etc.

**Checkpointer**:
- Performs periodic checkpoints (see WAL section)
- Writes all dirty buffers to disk
- Spreads I/O over checkpoint interval to avoid spikes
- Configured via `checkpoint_timeout`, `checkpoint_completion_target`

### Buffer Manager Statistics

The `pg_buffercache` extension provides visibility into buffer contents:

```sql
SELECT c.relname,
       count(*) AS buffers,
       pg_size_pretty(count(*) * 8192) AS size
FROM pg_buffercache b
  JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
WHERE b.reldatabase IN (0, (SELECT oid FROM pg_database
                             WHERE datname = current_database()))
GROUP BY c.relname
ORDER BY count(*) DESC
LIMIT 10;
```

**Key metrics:**
- **cache hit ratio**: Percentage of page accesses served from cache
- **buffers_checkpoint**: Buffers written by checkpointer
- **buffers_clean**: Buffers written by background writer
- **buffers_backend**: Buffers written by backend processes

### Performance Tuning

**shared_buffers** configuration:
- Default: 128 MB (too small for production)
- Recommendation: 25% of system RAM (up to 8-16 GB)
- Beyond 16 GB often shows diminishing returns
- OS page cache provides additional caching

**Monitoring buffer cache effectiveness:**

```sql
SELECT
  sum(heap_blks_read) as heap_read,
  sum(heap_blks_hit) as heap_hit,
  sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0)
    AS cache_hit_ratio
FROM pg_statio_user_tables;
```

Target cache hit ratio: > 0.99 for OLTP workloads

### Local Buffers

In addition to shared buffers, each backend maintains **local buffers** for temporary tables:

```c
/* Configured via temp_buffers (default 8MB) */
Buffer LocalBufferAlloc(SMgrRelation smgr, ForkNumber forkNum,
                        BlockNumber blockNum, bool *foundPtr);
```

**Characteristics:**
- Private to each backend process
- No locking needed (single-threaded access)
- Not persistent across sessions
- Simpler implementation than shared buffers

### Critical Code Paths

**Core buffer manager functions** (`src/backend/storage/buffer/bufmgr.c`):

- `ReadBuffer` (line ~465): Main entry point for reading pages
- `ReadBufferExtended` (line ~486): Extended version with options
- `ReleaseBuffer` (line ~2040): Release buffer pin
- `MarkBufferDirty` (line ~2208): Mark buffer as modified
- `LockBuffer` (line ~3016): Acquire buffer content lock
- `FlushBuffer` (line ~2695): Write dirty buffer to disk
- `StrategyGetBuffer` (line ~115 in freelist.c): Clock sweep implementation

## Heap Access Method

### Overview

The heap access method is PostgreSQL's default storage mechanism for table data. Located primarily in `src/backend/access/heap/` (with heapam.c containing 9,337 lines), it implements an unordered collection of tuples organized in pages. The term "heap" refers to the unordered nature—tuples are not stored in any particular order, unlike index-organized tables in some other database systems.

The heap access method is responsible for:
- Storing and retrieving tuples
- Implementing MVCC tuple visibility
- Supporting tuple updates and deletes
- Managing tuple chains (HOT - Heap-Only Tuples)
- Coordinating with VACUUM for space reclamation

### Heap Tuple Format

A complete heap tuple consists of:

```
+-------------------+
| HeapTupleHeader   | ~23 bytes + alignment
+-------------------+
| NULL Bitmap       | ceil(natts/8) bytes (if any nullable cols)
+-------------------+
| OID               | 4 bytes (if table has OIDs - deprecated)
+-------------------+
| User Data         | Actual column values
|  - Fixed-length   |
|  - Varlena        |
+-------------------+
```

### Heap Tuple Header Details

```c
typedef struct HeapTupleFields
{
    TransactionId t_xmin;       /* inserting xact ID */
    TransactionId t_xmax;       /* deleting or locking xact ID */

    union
    {
        CommandId   t_cid;      /* inserting or deleting command ID */
        TransactionId t_xvac;   /* old-style VACUUM FULL xact ID */
    } t_field3;
} HeapTupleFields;
```

**Transaction ID fields:**

- **t_xmin**: Transaction that inserted this tuple
  - Used to determine if tuple is visible to other transactions
  - Never changes after tuple creation

- **t_xmax**: Transaction that deleted or locked this tuple
  - 0 (InvalidTransactionId) if tuple is current
  - Set on DELETE or UPDATE (which creates new version)
  - Also used for tuple locking (SELECT FOR UPDATE)

- **t_cid**: Command ID within transaction
  - Distinguishes multiple statements within same transaction
  - Used for intra-transaction visibility

### Heap Tuple Infomask Flags

The `t_infomask` and `t_infomask2` fields contain crucial tuple state information:

```c
/* t_infomask flags */
#define HEAP_HASNULL          0x0001  /* has null attribute(s) */
#define HEAP_HASVARWIDTH      0x0002  /* has variable-width attribute(s) */
#define HEAP_HASEXTERNAL      0x0004  /* has external stored attribute(s) */
#define HEAP_HASOID_OLD       0x0008  /* has OID (deprecated) */
#define HEAP_XMAX_KEYSHR_LOCK 0x0010  /* xmax is key-shared locker */
#define HEAP_COMBOCID         0x0020  /* t_cid is combo CID */
#define HEAP_XMAX_EXCL_LOCK   0x0040  /* xmax is exclusive locker */
#define HEAP_XMAX_LOCK_ONLY   0x0080  /* xmax is locker only, not deleter */

/* Tuple visibility flags */
#define HEAP_XMIN_COMMITTED   0x0100  /* t_xmin committed */
#define HEAP_XMIN_INVALID     0x0200  /* t_xmin aborted */
#define HEAP_XMAX_COMMITTED   0x0400  /* t_xmax committed */
#define HEAP_XMAX_INVALID     0x0800  /* t_xmax aborted */
#define HEAP_XMAX_IS_MULTI    0x1000  /* xmax is MultiXactId */
#define HEAP_UPDATED          0x2000  /* this is UPDATEd version of row */
#define HEAP_MOVED_OFF        0x4000  /* old-style VACUUM FULL */
#define HEAP_MOVED_IN         0x8000  /* old-style VACUUM FULL */
```

These flags optimize visibility checks by caching transaction status information on the tuple itself, avoiding repeated lookups in CLOG (commit log).

### Heap Tuple Operations

#### Inserting Tuples

```c
/* Main insertion function */
void heap_insert(Relation relation, HeapTuple tup, CommandId cid,
                 int options, BulkInsertState bistate);
```

**Insertion process:**

1. **Find page with free space**:
   - Check FSM (Free Space Map) for suitable page
   - If no page found, extend relation with new page

2. **Lock buffer** exclusively

3. **Prepare tuple**:
   - Set t_xmin to current transaction ID
   - Set t_xmax to 0 (invalid)
   - Set t_cid to current command ID
   - Clear visibility hint bits initially

4. **Write WAL record** (if not temp table):
   - Create XLOG_HEAP_INSERT record
   - Insert WAL record before modifying page
   - Get LSN of WAL record

5. **Add tuple to page**:
   - Call PageAddItem to add tuple
   - Update page LSN

6. **Update indexes**:
   - Insert entries in all indexes
   - Each index insert also WAL-logged

7. **Update FSM** if significant free space remains

#### Reading Tuples

Sequential scan implementation:

```c
HeapTuple heap_getnext(TableScanDesc sscan, ScanDirection direction);
```

**Scan process:**

1. **Read page** via buffer manager
2. **Iterate through item pointers**
3. **For each tuple**:
   - Check visibility using snapshot
   - Skip if not visible to current transaction
   - Return visible tuple
4. **Move to next page** when current page exhausted

Index scan:

```c
bool heap_fetch(Relation relation, Snapshot snapshot,
                HeapTuple tuple, Buffer *userbuf);
```

Uses TID (tuple identifier = block number + item number) from index to directly fetch tuple.

#### Updating Tuples

```c
TM_Result heap_update(Relation relation, ItemPointer otid,
                      HeapTuple newtup, CommandId cid,
                      Snapshot crosscheck, bool wait,
                      TM_FailureData *tmfd, LockTupleMode *lockmode);
```

**Update strategies:**

**1. HOT Update (Heap-Only Tuple)**

When new tuple fits on same page AND no indexed columns changed:

```
Old Tuple                New Tuple
+--------+              +--------+
| t_xmin | -----------> | t_xmin | (new)
| t_xmax | (current)    | t_xmax | (0)
| t_ctid | -----------> | t_ctid | (self-ref)
+--------+              +--------+
   ↑                        ↑
   |                        |
Line Ptr 1              Line Ptr 2
(LP_REDIRECT)           (LP_NORMAL)
```

**Benefits:**
- No index updates needed (huge performance win)
- Reduced bloat
- Faster VACUUM

**Requirements:**
- Enough space on same page
- No indexed columns modified
- Page not full of redirect pointers

**2. Normal Update**

When HOT not possible:

1. Insert new tuple (possibly on different page)
2. Update all indexes to point to new tuple
3. Set old tuple's t_xmax to current XID
4. Set old tuple's t_ctid to point to new tuple

#### Deleting Tuples

```c
TM_Result heap_delete(Relation relation, ItemPointer tid,
                      CommandId cid, Snapshot crosscheck,
                      bool wait, TM_FailureData *tmfd,
                      bool changingPart);
```

**Delete process:**

1. **Fetch tuple** using TID
2. **Check visibility**: Ensure tuple is visible and not locked
3. **Mark deleted**:
   - Set t_xmax to current transaction ID
   - Set HEAP_UPDATED flag in t_infomask
4. **Write WAL record**
5. **Update indexes**: Mark entries as dead

**Actual space reclamation** happens later during VACUUM.

### HOT (Heap-Only Tuple) Updates

HOT is one of PostgreSQL's most important performance optimizations, introduced in version 8.3.

**Problem HOT solves:**

Traditional updates require:
- New heap tuple
- Update every index (expensive for tables with many indexes)
- Bloat in indexes and heap

**HOT solution:**

When conditions allow, keep old and new tuple versions on same page with a redirect pointer, avoiding index updates.

**HOT chain example:**

```
Page N
+------------------+
| Item Ptr 1       | → LP_REDIRECT → Item Ptr 3
| Item Ptr 2       | → LP_NORMAL → Old Tuple (dead)
| Item Ptr 3       | → LP_NORMAL → New Tuple (current)
+------------------+
         ↑
         |
    Index Entry
    (unchanged)
```

**Index still points to Item Ptr 1**, which redirects to Item Ptr 3 (current tuple). No index update needed!

**HOT pruning:**

`heap_page_prune()` cleans up HOT chains:
- Removes dead tuples in middle of chain
- Collapses redirect pointers
- Reclaims space within page

**Statistics:**

```sql
SELECT n_tup_upd, n_tup_hot_upd,
       n_tup_hot_upd::float / nullif(n_tup_upd, 0) AS hot_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'public';
```

High HOT ratio (close to 1.0) indicates efficient updates.

### Tuple Locking

PostgreSQL supports row-level locking for SELECT FOR UPDATE/SHARE:

**Lock modes:**
- **FOR KEY SHARE**: Weakest, blocks UPDATE of key columns
- **FOR SHARE**: Blocks UPDATE and DELETE
- **FOR NO KEY UPDATE**: Blocks UPDATE of key columns and DELETE
- **FOR UPDATE**: Strongest, blocks all concurrent modifications

**Implementation:**

Locks stored in tuple header's t_xmax field:
- For single locker: t_xmax contains locker's XID
- For multiple lockers: t_xmax contains MultiXactId

**MultiXactId:**

```c
typedef struct MultiXactMember
{
    TransactionId xid;
    MultiXactStatus status;  /* lock mode */
} MultiXactMember;
```

Allows multiple transactions to hold compatible locks on same tuple.

### Heap File Organization

Heap relations are stored as files in `$PGDATA/base/<database_oid>/`:

```
<relation_oid>      - Main data fork
<relation_oid>_fsm  - Free Space Map fork
<relation_oid>_vm   - Visibility Map fork
<relation_oid>_init - Initialization fork (for unlogged tables)
```

**Forks:**

```c
typedef enum ForkNumber
{
    MAIN_FORKNUM = 0,
    FSM_FORKNUM,
    VISIBILITYMAP_FORKNUM,
    INIT_FORKNUM
} ForkNumber;
```

### Heap Statistics and Monitoring

```sql
-- Table size
SELECT pg_size_pretty(pg_total_relation_size('tablename'));

-- Live vs dead tuples
SELECT relname, n_live_tup, n_dead_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup, 0), 4) AS dead_ratio
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Last vacuum/analyze
SELECT relname, last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables;
```

### Heap Access Method API

PostgreSQL 12+ introduced a pluggable table access method API:

```c
typedef struct TableAmRoutine
{
    /* Scan operations */
    TableScanDesc (*scan_begin) (...);
    bool (*scan_getnextslot) (...);
    void (*scan_end) (...);

    /* Tuple operations */
    void (*tuple_insert) (...);
    TM_Result (*tuple_update) (...);
    TM_Result (*tuple_delete) (...);

    /* ... many more operations */
} TableAmRoutine;
```

This allows alternative storage engines (e.g., columnar storage, in-memory tables) while maintaining compatibility with PostgreSQL's query processing.

### Performance Considerations

**Fill factor:**

```sql
ALTER TABLE tablename SET (fillfactor = 90);
```

Reserves space on each page for HOT updates:
- Default: 100 (no reserved space)
- Recommendation: 90 for frequently updated tables
- Trade-off: Slightly larger table vs. better update performance

**VACUUM and bloat:**

Regular VACUUM is essential:
- Reclaims dead tuple space
- Updates FSM and VM
- Prevents transaction ID wraparound
- Improves query performance

```sql
-- Estimate bloat
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
       round((CASE WHEN otta=0 THEN 0.0 ELSE sml.relpages/otta::numeric END)::numeric, 1) AS tbloat
FROM (
  SELECT schemaname, tablename, cc.relpages, bs,
         CEIL((cc.reltuples*((datahdr+ma-(CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta
  FROM (
    SELECT schemaname, tablename, reltuples, relpages,
           (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
           (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT schemaname, tablename, hdr, ma, bs, reltuples, relpages,
             SUM((1-null_frac)*avg_width) AS datawidth,
             MAX(null_frac) AS maxfracsum,
             hdr+(
               SELECT 1+count(*)/8
               FROM pg_stats s2
               WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
             ) AS nullhdr
      FROM pg_stats s, (SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 8 AS ma) AS constants
      GROUP BY 1,2,3,4,5,6,7
    ) AS foo
  ) AS rs
  JOIN pg_class cc ON cc.relname = rs.tablename
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = rs.schemaname
) AS sml
ORDER BY tbloat DESC;
```

## Write-Ahead Logging

### Overview

Write-Ahead Logging (WAL) is the cornerstone of PostgreSQL's reliability and recovery mechanisms. Implemented primarily in `src/backend/access/transam/xlog.c` (9,584 lines), WAL ensures that all changes to the database can be recovered after a crash and provides the foundation for replication.

The WAL protocol follows a simple but powerful principle: **write the change log to persistent storage before applying changes to data files**. This guarantees that if the system crashes, we can replay the log to reconstruct the database state.

### WAL Principles

**The WAL Rule:**

```
Before a data page is written to permanent storage:
1. All log records describing changes to that page must be written to disk
2. This is enforced by checking the page's LSN against flushed WAL position
```

**Benefits:**

1. **Crash Recovery**: Database can be restored to consistent state
2. **Performance**: Transforms random writes into sequential writes
3. **Durability**: ACID compliance with guaranteed persistence
4. **Replication**: WAL stream enables physical replication
5. **Point-in-Time Recovery**: Archive logs allow recovery to any past moment

### LSN (Log Sequence Number)

Every byte in the WAL stream has a unique identifier called an LSN:

```c
typedef uint64 XLogRecPtr;  /* Also called LSN */
```

**LSN structure:**

- 64-bit unsigned integer
- Represents byte offset in the logical WAL stream
- Lower 32 bits: offset within a WAL segment
- Upper 32 bits: segment number

**Example:**
```
LSN: 0x0/16C4000
     ↑  ↑
     |  +-- Offset within segment
     +----- Segment number
```

Every page header contains the LSN of the last WAL record that modified it (`pd_lsn`).

### WAL Record Structure

WAL records have a header followed by data:

```c
typedef struct XLogRecord
{
    uint32      xl_tot_len;     /* total record length */
    TransactionId xl_xid;       /* xact id */
    XLogRecPtr  xl_prev;        /* ptr to previous record */
    uint8       xl_info;        /* flag bits */
    RmgrId      xl_rmid;        /* resource manager ID */
    uint32      xl_crc;         /* CRC for entire record */

    /* Followed by variable-length data */
} XLogRecord;
```

**Resource Managers (RmgrId):**

PostgreSQL has different resource managers for different subsystems:

```c
/* Some key resource managers */
#define RM_XLOG_ID          0   /* WAL management */
#define RM_XACT_ID          1   /* Transaction commit/abort */
#define RM_SMGR_ID          2   /* Storage manager */
#define RM_HEAP_ID          10  /* Heap operations */
#define RM_BTREE_ID         11  /* B-tree operations */
#define RM_HASH_ID          12  /* Hash index operations */
#define RM_GIN_ID           13  /* GIN index operations */
#define RM_GIST_ID          14  /* GiST index operations */
#define RM_SEQ_ID           15  /* Sequences */
```

Each resource manager provides:
- `redo()`: Function to replay WAL record during recovery
- `desc()`: Function to describe record (for debugging)
- `identify()`: String identifier
- `startup()`, `cleanup()`: Recovery lifecycle hooks

### WAL Record Types

**Heap operations:**
```c
#define XLOG_HEAP_INSERT    0x00
#define XLOG_HEAP_DELETE    0x10
#define XLOG_HEAP_UPDATE    0x20
#define XLOG_HEAP_HOT_UPDATE 0x30
#define XLOG_HEAP_LOCK      0x50
```

**Transaction operations:**
```c
#define XLOG_XACT_COMMIT    0x00
#define XLOG_XACT_ABORT     0x20
```

**B-tree operations:**
```c
#define XLOG_BTREE_INSERT_LEAF   0x00
#define XLOG_BTREE_INSERT_UPPER  0x10
#define XLOG_BTREE_SPLIT_L       0x20
#define XLOG_BTREE_DELETE        0x40
```

### WAL Buffer and Writing

WAL records are first written to shared WAL buffers:

```c
/* Configured via wal_buffers (default: 1/32 of shared_buffers, min 64KB) */
static char *XLogCtl->pages;  /* WAL buffer space */
```

**Write process:**

1. **Backend generates WAL record** for data modification
2. **Acquire WAL insertion lock**
3. **Copy WAL record to WAL buffer**
4. **Release WAL insertion lock**
5. **At commit or when buffer fills**: Flush WAL to disk
6. **Return success** only after WAL is on disk (for durable commits)

**WAL Writer Process:**

Background process that periodically flushes WAL buffers:

```c
/* Configuration */
wal_writer_delay = 200ms     /* How often WAL writer wakes up */
wal_writer_flush_after = 1MB /* Write and flush if this much unflushed */
```

### WAL Files and Segments

WAL is stored in files in `$PGDATA/pg_wal/`:

```
pg_wal/
  00000001000000000000000A
  00000001000000000000000B
  00000001000000000000000C
  ...
```

**File naming:**
```
TTTTTTTTXXXXXXXXYYYYYYYY
|       |       |
|       |       +-- Segment number within timeline (256MB each)
|       +---------- Upper 32 bits of LSN
+------------------ Timeline ID
```

**WAL segment size**: 16MB by default (configurable at initdb)

**WAL recycling**: Old segments are renamed and reused rather than deleted

### Full Page Writes (FPW)

**The torn page problem:**

If the system crashes during a partial page write (e.g., 8KB write but only 4KB made it to disk), the page is corrupted.

**Solution: Full Page Writes**

After each checkpoint, the first modification to a page writes the **entire page** to WAL:

```c
typedef struct BkpBlock
{
    RelFileNode node;      /* which relation */
    ForkNumber  fork;      /* which fork */
    BlockNumber block;     /* which block */
    uint16      hole_offset;  /* hole start offset */
    uint16      hole_length;  /* hole length */
    /* Followed by full page image (minus any hole) */
} BkpBlock;
```

**Optimization - hole punching:**

Most pages have free space in the middle. WAL records only the data before and after the hole, saving space.

**Configuration:**

```
full_page_writes = on  /* Default and strongly recommended */
```

Disabling is dangerous but might be acceptable with reliable storage (battery-backed write cache).

### Checkpoints

A checkpoint is a known good state from which recovery can start:

**Checkpoint process:**

1. **Write all dirty buffers** to disk
2. **Write a checkpoint record** to WAL containing:
   - Redo pointer (WAL location where recovery should start)
   - System state (next XID, next OID, etc.)
3. **Update pg_control** file with checkpoint location

**Recovery then:**
1. Read pg_control to find latest checkpoint
2. Start replay from checkpoint's redo pointer
3. Replay all WAL records until end of WAL

**Checkpoint configuration:**

```
checkpoint_timeout = 5min           /* Maximum time between checkpoints */
checkpoint_completion_target = 0.9  /* Spread writes over 90% of interval */
max_wal_size = 1GB                  /* Trigger checkpoint if WAL grows */
min_wal_size = 80MB                 /* Recycle WAL files below this */
```

**Checkpoint spreading:**

To avoid I/O spikes, PostgreSQL spreads checkpoint writes over time:

```
checkpoint_completion_target = 0.9

Time: |----checkpoint_timeout = 5min----|
      |                                  |
Write:|===========(write for 4.5min)====|==| (finalize)
```

### Recovery Process

**Crash recovery** (automatic on startup after crash):

```c
/* src/backend/access/transam/xlog.c */
void StartupXLOG(void)
{
    /* 1. Read control file */
    ReadControlFile();

    /* 2. Locate checkpoint record */
    record = ReadCheckpointRecord(CheckPointLoc);

    /* 3. Replay WAL from checkpoint redo point */
    for (record = ReadRecord(RedoStartLSN); record != NULL;
         record = ReadRecord(NextRecPtr))
    {
        /* Apply record using appropriate resource manager */
        RmgrTable[record->xl_rmid].rm_redo(record);
    }

    /* 4. Create end-of-recovery checkpoint */
    CreateCheckPoint(CHECKPOINT_END_OF_RECOVERY);
}
```

**Point-in-Time Recovery (PITR):**

Restore from base backup and replay archived WAL:

```
# postgresql.conf
restore_command = 'cp /archive/%f %p'
recovery_target_time = '2025-11-19 10:00:00'
```

### WAL Archiving

For PITR and replication:

```
# postgresql.conf
wal_level = replica              # or 'logical'
archive_mode = on
archive_command = 'cp %p /archive/%f'
```

**WAL levels:**

- **minimal**: Only crash recovery (no archiving/replication)
- **replica**: Physical replication supported
- **logical**: Logical decoding/replication supported

### WAL and Replication

**Streaming Replication:**

Standby servers connect and stream WAL in real-time:

1. **Primary** sends WAL records as they're generated
2. **Standby** receives and replays them
3. **Synchronous replication**: Wait for standby acknowledgment before commit

**Configuration:**

```
# Primary
wal_level = replica
max_wal_senders = 10
synchronous_standby_names = 'standby1'

# Standby
primary_conninfo = 'host=primary port=5432 ...'
hot_standby = on
```

### WAL Monitoring

```sql
-- Current WAL position
SELECT pg_current_wal_lsn();

-- WAL generation rate
SELECT
  wal_records,
  wal_fpi,  -- full page images
  wal_bytes,
  pg_size_pretty(wal_bytes) AS wal_size
FROM pg_stat_wal;

-- Replication lag
SELECT
  client_addr,
  pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes,
  replay_lag
FROM pg_stat_replication;
```

### WAL Internals and Performance

**WAL insertion locks:**

PostgreSQL 9.4+ uses multiple WAL insertion locks to reduce contention:

```c
#define NUM_XLOGINSERT_LOCKS  8
```

Backends can insert WAL records in parallel, though commits still serialize at flush time.

**WAL compression:**

```
wal_compression = on  /* Compress full page images (PostgreSQL 9.5+) */
```

Can significantly reduce WAL volume for workloads with large FPW.

**fsync methods:**

```
fsync = on                    /* Must be on for durability */
wal_sync_method = fdatasync   /* OS-dependent, fdatasync often best */
```

**Tuning for performance:**

```
# Larger WAL buffers for write-heavy workloads
wal_buffers = 16MB

# Less frequent checkpoints for write-heavy workloads
checkpoint_timeout = 15min
max_wal_size = 2GB

# Async commit for non-critical data (trades durability for speed)
synchronous_commit = off
```

**synchronous_commit modes:**

- **on**: Wait for WAL flush (full durability)
- **remote_write**: Wait for standby to write (not flush)
- **remote_apply**: Wait for standby to apply
- **local**: Wait for local flush only (ignore standbys)
- **off**: Don't wait (crash may lose last few transactions)

### WAL Record Decoding

The `pg_waldump` utility decodes WAL files:

```bash
pg_waldump -p $PGDATA/pg_wal/ -s 0/16C4000 -n 10
```

Example output:
```
rmgr: Heap        len (rec/tot):     54/   178, tx:        567, lsn: 0/016C4000,
  prev 0/016C3FC0, desc: INSERT off 3, blkref #0: rel 1663/13593/16384 blk 0 FPW
rmgr: Transaction len (rec/tot):     34/    34, tx:        567, lsn: 0/016C40B8,
  prev 0/016C4000, desc: COMMIT 2025-11-19 10:00:00.123456 UTC
```

Useful for debugging and forensic analysis.

## Multi-Version Concurrency Control

### Overview

Multi-Version Concurrency Control (MVCC) is PostgreSQL's approach to handling concurrent transactions. Instead of locking data for the duration of a read, PostgreSQL maintains multiple versions of each row, allowing readers and writers to operate without blocking each other.

MVCC provides:
- **High concurrency**: Readers never block writers, writers never block readers
- **Consistent snapshots**: Each transaction sees a consistent view of data
- **Isolation levels**: Support for all SQL standard isolation levels
- **No read locks**: SELECT never acquires locks on data

### Core MVCC Principles

**Version visibility:**

Each transaction sees a snapshot of the database at a specific point in time. Whether a tuple version is visible depends on:

1. The transaction ID that created it (t_xmin)
2. The transaction ID that deleted it (t_xmax)
3. The viewing transaction's snapshot

**Tuple version example:**

```
Table: accounts
Row ID: 1

Version 1:  t_xmin=100, t_xmax=0,   balance=1000  (created by XID 100, still current)
Version 2:  t_xmin=105, t_xmax=0,   balance=1500  (created by XID 105, is UPDATE)
Version 1': t_xmin=100, t_xmax=105, balance=1000  (marked deleted by XID 105)
```

Transaction 103 would see Version 1 (balance=1000)
Transaction 107 would see Version 2 (balance=1500)

### Snapshot Structure

A snapshot captures which transactions are visible:

```c
typedef struct SnapshotData
{
    SnapshotType snapshot_type;

    TransactionId xmin;  /* All XID < xmin are either committed or aborted */
    TransactionId xmax;  /* All XID >= xmax are not yet committed */

    TransactionId *xip;  /* Array of in-progress XIDs at snapshot time */
    uint32 xcnt;         /* Count of in-progress XIDs */

    TransactionId subxip[PGPROC_MAX_CACHED_SUBXIDS];
    int32 subxcnt;       /* Count of subtransaction XIDs */

    CommandId curcid;    /* Current command ID */
} SnapshotData;
```

**Snapshot types:**

- **MVCC Snapshot**: Regular transaction snapshot (READ COMMITTED gets new one per statement)
- **Self Snapshot**: See own changes, used during query execution
- **Dirty Snapshot**: See all versions (used by VACUUM)
- **Historic Snapshot**: For logical decoding

### Visibility Rules

The core visibility check (`HeapTupleSatisfiesMVCC` in `src/backend/access/heap/heapam_visibility.c`):

```c
bool HeapTupleSatisfiesMVCC(HeapTuple htup, Snapshot snapshot, Buffer buffer)
{
    /* 1. Check if tuple was created by a transaction visible to snapshot */
    if (XidInMVCCSnapshot(htup->t_xmin, snapshot))
        return false;  /* Creator not yet committed when snapshot taken */

    /* 2. Check if tuple has been deleted/updated */
    if (!TransactionIdIsValid(htup->t_xmax))
        return true;  /* Not deleted, visible */

    /* 3. Check if deleter is visible to snapshot */
    if (XidInMVCCSnapshot(htup->t_xmax, snapshot))
        return true;  /* Deleter not committed when snapshot taken */

    return false;  /* Deleted by committed transaction */
}
```

**Detailed visibility rules:**

1. **Tuple created after snapshot**: Not visible
2. **Tuple deleted before snapshot**: Not visible
3. **Tuple created by aborted transaction**: Not visible
4. **Tuple deleted by aborted transaction**: Visible
5. **Tuple created and deleted by in-progress transaction**: Check if it's our own transaction

### Transaction ID Management

**Transaction ID (XID):**

```c
typedef uint32 TransactionId;

#define InvalidTransactionId      0
#define BootstrapTransactionId    1
#define FrozenTransactionId       2
#define FirstNormalTransactionId  3
```

**XID allocation:**

```c
TransactionId GetNewTransactionId(bool isSubXact);
```

XIDs are allocated sequentially. PostgreSQL can handle ~2 billion transactions before wraparound.

**XID wraparound problem:**

XIDs are 32-bit, forming a circular space:

```
      newest XID
           ↓
    ... 2B-1, 0, 1, 2 ...
           ↑
      oldest XID
```

After 2^31 transactions, old tuples would appear to be in the future!

**Solution: Freezing**

VACUUM "freezes" old tuples by setting t_xmin to FrozenTransactionId (2):

```sql
-- Freeze tuples when XID age exceeds this
vacuum_freeze_min_age = 50000000

-- Force aggressive VACUUM when table age exceeds this
vacuum_freeze_table_age = 150000000

-- Prevent wraparound catastrophe
autovacuum_freeze_max_age = 200000000
```

### Transaction Status: CLOG

The Commit Log (CLOG, also called pg_xact) tracks transaction status:

```
XID → Status (committed, aborted, in-progress, sub-committed)
```

Located in `$PGDATA/pg_xact/`, stores 2 bits per transaction:

- `00`: In progress
- `01`: Committed
- `10`: Aborted
- `11`: Sub-committed

**CLOG lookup:**

```c
XidStatus TransactionIdGetStatus(TransactionId xid);
```

**Hint bits optimization:**

To avoid repeated CLOG lookups, PostgreSQL caches transaction status in tuple headers:

```c
#define HEAP_XMIN_COMMITTED  0x0100
#define HEAP_XMIN_INVALID    0x0200
#define HEAP_XMAX_COMMITTED  0x0400
#define HEAP_XMAX_INVALID    0x0800
```

First transaction to check a tuple's visibility:
1. Looks up XID in CLOG
2. Sets hint bit on tuple
3. Marks buffer dirty

Subsequent checks use hint bit, avoiding CLOG lookup.

### Isolation Levels

PostgreSQL implements SQL standard isolation levels using MVCC:

**Read Uncommitted** (treated as Read Committed):
```sql
BEGIN TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
```
- Gets new snapshot for each statement
- Sees committed changes from other transactions between statements

**Read Committed** (default):
```sql
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
```
- Gets new snapshot for each statement
- Most common isolation level

**Repeatable Read**:
```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
```
- Single snapshot for entire transaction
- Prevents non-repeatable reads
- Can see phantom reads in theory, but PostgreSQL prevents them

**Serializable**:
```sql
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```
- True serializability via Serializable Snapshot Isolation (SSI)
- Detects read-write conflicts that could violate serializability
- May abort transactions with "could not serialize" error

### Serializable Snapshot Isolation (SSI)

PostgreSQL's SERIALIZABLE implementation uses predicate locking:

```c
/* Track dangerous read-write patterns */
typedef struct SERIALIZABLEXACT
{
    VirtualTransactionId vxid;

    /* Conflicts with other transactions */
    dlist_head possibleUnsafeConflicts;

    /* Read locks */
    PREDICATELOCKTARGETTAG *predicatelocktarget;
} SERIALIZABLEXACT;
```

**Conflict detection:**

SSI looks for dangerous structures:

```
T1: Read A  → Write B
T2: Read B  → Write A
```

If both occur, one transaction is aborted to prevent anomaly.

**Performance**: SERIALIZABLE has overhead but provides strongest guarantees.

### Subtransactions

Savepoints create subtransactions:

```sql
BEGIN;
  INSERT INTO accounts VALUES (1, 1000);
  SAVEPOINT sp1;
    UPDATE accounts SET balance = 1100 WHERE id = 1;
    -- Error occurs
  ROLLBACK TO sp1;  -- Undo UPDATE but keep INSERT
COMMIT;
```

**Implementation:**

Subtransactions get their own XID (SubTransactionId):

```c
typedef uint32 SubTransactionId;
```

CLOG tracks parent-child relationships. A subtransaction is committed only if its parent commits.

### VACUUM and Dead Tuple Cleanup

MVCC creates dead tuple versions that must be cleaned up:

**VACUUM operations:**

1. **Identify dead tuples**: Check visibility (no active snapshot can see them)
2. **Remove from indexes**: Mark index entries as dead
3. **Remove from heap**: Reclaim space, set item pointers to LP_UNUSED
4. **Update FSM**: Record available free space
5. **Update VM**: Mark pages as all-visible if appropriate
6. **Freeze old tuples**: Prevent XID wraparound
7. **Truncate empty pages** at end of table

**VACUUM types:**

```sql
-- Regular VACUUM (reclaims space within file)
VACUUM tablename;

-- VACUUM FULL (rewrites entire table, exclusive lock)
VACUUM FULL tablename;

-- Autovacuum (automatic background process)
```

**Autovacuum configuration:**

```
autovacuum = on
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.2

-- Trigger autovacuum when:
-- dead_tuples > threshold + scale_factor * table_size
-- Example: 10M row table → vacuum when 2M+ dead tuples
```

### Bloat Management

MVCC can cause table bloat:

**Bloat causes:**
- High UPDATE/DELETE rate
- Long-running transactions (prevent VACUUM from cleaning up)
- Insufficient autovacuum tuning

**Monitoring bloat:**

```sql
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  round(100 * (pg_total_relation_size(schemaname||'.'||tablename)::numeric /
    nullif(pg_relation_size(schemaname||'.'||tablename), 0)), 1) AS bloat_pct
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

**Reducing bloat:**

1. Tune autovacuum to run more aggressively
2. Use HOT updates (ensure indexed columns not updated)
3. Set appropriate fillfactor
4. Avoid long-running transactions
5. Consider partitioning for large tables
6. Periodic VACUUM FULL or table rewrite for severe bloat

### MVCC Performance Implications

**Advantages:**
- Readers never block writers
- Writers never block readers
- No read locks
- High concurrency

**Costs:**
- Storage overhead (multiple tuple versions)
- VACUUM overhead
- Index updates for every UPDATE (unless HOT)
- Bloat if not properly managed

**Best practices:**
1. Monitor autovacuum activity
2. Tune autovacuum for workload
3. Avoid long-running transactions
4. Use HOT updates when possible
5. Regular monitoring of table bloat

## Index Access Methods

### Overview

PostgreSQL provides six built-in index types, each optimized for different data types and query patterns. The index access method API allows extensions to add new index types, making PostgreSQL highly extensible.

All index types share a common interface defined in `src/include/access/amapi.h`:

```c
typedef struct IndexAmRoutine
{
    NodeTag     type;

    /* Index build callbacks */
    ambuild_function ambuild;
    ambuildempty_function ambuildempty;

    /* Index scan callbacks */
    aminsert_function aminsert;
    ambulkdelete_function ambulkdelete;
    amvacuumcleanup_function amvacuumcleanup;

    /* Index scan functions */
    ambeginscan_function ambeginscan;
    amrescan_function amrescan;
    amgettuple_function amgettuple;

    /* ... many more callbacks */
} IndexAmRoutine;
```

### B-tree Indexes

**Default and most versatile index type** (`src/backend/access/nbtree/`).

**Characteristics:**
- Balanced tree structure
- Logarithmic search time: O(log N)
- Ordered data (supports range scans)
- Supports multi-column indexes
- Handles NULL values

**When to use:**
- Equality comparisons: `WHERE id = 5`
- Range queries: `WHERE created_at BETWEEN ... AND ...`
- Sorting: `ORDER BY name`
- Pattern matching: `WHERE name LIKE 'John%'`
- IS NULL / IS NOT NULL

**Supported operators:**
```
<, <=, =, >=, >, BETWEEN, IN, IS NULL, IS NOT NULL
```

**Structure:**

```
                    [Root Page]
                   /     |     \
            [Internal] [Internal] [Internal]
            /    \      /    \      /    \
        [Leaf] [Leaf] [Leaf] [Leaf] [Leaf] [Leaf]
          ↕      ↕      ↕      ↕      ↕      ↕
        (Doubly-linked leaf pages for efficient range scans)
```

**B-tree page structure:**

```c
typedef struct BTPageOpaqueData
{
    BlockNumber btpo_prev;      /* Left sibling */
    BlockNumber btpo_next;      /* Right sibling */
    uint32      btpo_level;     /* Tree level (0 = leaf) */
    uint16      btpo_flags;     /* Page type and status flags */
    BTCycleId   btpo_cycleid;   /* Vacuum cycle ID */
} BTPageOpaqueData;
```

**Index tuple format:**

```c
typedef struct IndexTupleData
{
    ItemPointerData t_tid;  /* TID of heap tuple */
    unsigned short t_info;  /* Various info */

    /* Followed by indexed attribute values */
} IndexTupleData;
```

**B-tree operations:**

**Insert** (`_bt_doinsert` in `nbtree.c`):
1. Descend tree to find correct leaf page
2. If page has space: Insert tuple
3. If page full: Split page, propagate split up tree

**Search** (`_bt_search`):
1. Start at root
2. Binary search within page to find downlink
3. Descend to child
4. Repeat until leaf page
5. Scan leaf page for matching tuples

**Page split:**
```
Before:
[Page A: 1,2,3,4,5,6,7,8] → FULL

After split:
[Page A: 1,2,3,4] ↔ [Page B: 5,6,7,8]
         ↑                    ↑
         └─── Parent: 4, 8 ───┘
```

**Unique indexes:**

```sql
CREATE UNIQUE INDEX idx_email ON users(email);
```

Enforces uniqueness by checking for existing entry before insert.

**Multi-column indexes:**

```sql
CREATE INDEX idx_name ON users(last_name, first_name);
```

Useful for queries on:
- `WHERE last_name = 'Smith'`
- `WHERE last_name = 'Smith' AND first_name = 'John'`

Not useful for:
- `WHERE first_name = 'John'` (doesn't use index)

**Index-only scans:**

If all needed columns are in index:

```sql
CREATE INDEX idx_covering ON orders(customer_id, order_date);
SELECT order_date FROM orders WHERE customer_id = 123;
```

PostgreSQL can satisfy query from index alone (if visibility map indicates pages are all-visible).

**B-tree deduplication** (PostgreSQL 13+):

Multiple identical keys stored compactly:

```
Before: (1,tid1), (1,tid2), (1,tid3), (1,tid4)
After:  (1,[tid1,tid2,tid3,tid4])
```

Reduces index size for non-unique indexes.

### Hash Indexes

**Hash-based lookup** (`src/backend/access/hash/`).

**Characteristics:**
- Hash function maps keys to bucket numbers
- O(1) average search time
- Only equality searches
- Not crash-safe before PostgreSQL 10
- Smaller than B-tree for equality-only workloads

**When to use:**
- Only equality comparisons: `WHERE id = 5`
- No need for ordering or range scans
- Consider B-tree instead for versatility

**Supported operators:**
```
= only
```

**Structure:**

```
Hash Function
     ↓
[Bucket 0] → [Overflow Page] → [Overflow Page]
[Bucket 1] → [Overflow Page]
[Bucket 2]
...
[Bucket N]
```

**Hash page types:**

```c
#define LH_META_PAGE         0  /* Meta page (bucket info) */
#define LH_BUCKET_PAGE       1  /* Primary bucket page */
#define LH_OVERFLOW_PAGE     2  /* Overflow page */
#define LH_BITMAP_PAGE       3  /* Bitmap of free pages */
```

**Example:**

```sql
CREATE INDEX idx_hash ON users USING HASH (email);
SELECT * FROM users WHERE email = 'user@example.com';
```

**Hash function:**

Uses high-quality hash function to minimize collisions:

```c
uint32 hash_any(const unsigned char *k, int keylen);
```

**Bucket splitting:**

When bucket gets too full, hash index can split it:

```
Before:
Hash(key) % 8 → Bucket 0

After split:
Hash(key) % 16 → Bucket 0 or Bucket 8
```

**Performance:**

- Slightly faster than B-tree for equality
- Cannot support range scans or ORDER BY
- Less commonly used than B-tree

### GiST (Generalized Search Tree)

**Extensible balanced tree** (`src/backend/access/gist/`).

**Characteristics:**
- Framework for custom index types
- Supports R-tree-like operations
- Handles multi-dimensional data
- Customizable via operator classes

**When to use:**
- Geometric data types (points, boxes, polygons)
- Full-text search (with tsvector)
- Range types
- Nearest-neighbor searches
- Custom data types

**Supported data types:**
- Geometric: point, box, circle, polygon, path
- Network: inet, cidr
- Text search: tsvector
- Range types: int4range, tsrange, etc.

**Structure:**

```
            [Root: MBR of all children]
           /           |            \
    [MBR: A-F]    [MBR: G-M]    [MBR: N-Z]
     /    \         /    \         /    \
  [A-C] [D-F]   [G-I] [J-M]   [N-Q] [R-Z]
   ↓     ↓       ↓     ↓       ↓     ↓
  Data  Data    Data  Data    Data  Data
```

MBR = Minimum Bounding Rectangle (or equivalent for key space)

**Example - geometric search:**

```sql
CREATE TABLE places (id int, location point);
CREATE INDEX idx_location ON places USING GIST (location);

-- Find places within box
SELECT * FROM places
WHERE location <@ box '((0,0),(10,10))';

-- Nearest neighbor (K-NN)
SELECT * FROM places
ORDER BY location <-> point '(5,5)'
LIMIT 10;
```

**Example - full-text search:**

```sql
CREATE INDEX idx_fts ON documents USING GIST (content_tsv);

SELECT * FROM documents
WHERE content_tsv @@ to_tsquery('postgresql & database');
```

**GiST operator classes:**

Each data type needs an operator class defining:
- `consistent`: Does entry match scan key?
- `union`: Compute bounding predicate for entries
- `penalty`: Cost of adding entry to subtree
- `picksplit`: How to split overfull page
- `same`: Are two entries identical?
- `distance`: For K-NN searches

**Lossy indexes:**

GiST can be lossy - index returns candidate set that must be rechecked:

1. Index scan finds candidates
2. Heap fetch retrieves actual tuples
3. Recheck condition on actual data

### SP-GiST (Space-Partitioned GiST)

**Space-partitioning trees** (`src/backend/access/spgist/`).

**Characteristics:**
- Non-balanced trees (unlike GiST)
- Supports partitioned search spaces
- Quad-trees, k-d trees, radix trees
- Excellent for certain data distributions

**When to use:**
- Geometric data with natural partitioning
- IP addresses (radix tree)
- Text with prefix searches
- Point data in 2D/3D space

**Example - quad-tree for points:**

```
            [Root: (-∞,∞) × (-∞,∞)]
          /        |        |        \
      NW Quad   NE Quad   SW Quad   SE Quad
     /  |  \   /  |  \   /  |  \   /  |  \
   ... ... ... ... ... ... ... ... ... ...
```

**Example - range types:**

```sql
CREATE TABLE reservations (room int, period tsrange);
CREATE INDEX idx_period ON reservations USING SPGIST (period);

-- Find overlapping reservations
SELECT * FROM reservations
WHERE period && '[2025-11-19 10:00, 2025-11-19 12:00)'::tsrange;
```

**Example - IP addresses:**

```sql
CREATE TABLE logs (ip inet, ...);
CREATE INDEX idx_ip ON logs USING SPGIST (ip);

-- Subnet search
SELECT * FROM logs WHERE ip <<= '192.168.1.0/24'::inet;
```

**SP-GiST operator classes:**

- `config`: Define tree node structure
- `choose`: Select subtree for insertion
- `picksplit`: How to split node
- `inner_consistent`: Which subtrees to search?
- `leaf_consistent`: Does leaf match query?

**Advantages over GiST:**

- Can be more efficient for naturally partitioned data
- Often smaller index size
- Better for skewed distributions

**Disadvantages:**

- Not balanced (worst case can be poor)
- More complex to implement operator classes

### GIN (Generalized Inverted Index)

**Inverted index for multi-value columns** (`src/backend/access/gin/`).

**Characteristics:**
- Stores mapping from values to tuples containing them
- Optimized for cases where column contains multiple values
- Excellent for full-text search
- Supports arrays, jsonb, tsvector

**When to use:**
- Full-text search
- Array contains queries
- JSONB queries
- Any multi-valued attributes

**Structure:**

```
Entry Tree (B-tree):
  "database" → Posting Tree → [TID1, TID2, TID17, ...]
  "index"    → Posting Tree → [TID3, TID5, TID17, ...]
  "postgres" → Posting Tree → [TID1, TID9, TID12, ...]
  ...
```

**Two-level structure:**

1. **Entry tree**: B-tree of unique indexed values (lexemes for text)
2. **Posting tree**: B-tree of tuple IDs for each entry

**Example - array search:**

```sql
CREATE TABLE products (id int, tags text[]);
CREATE INDEX idx_tags ON products USING GIN (tags);

-- Find products with specific tag
SELECT * FROM products WHERE tags @> ARRAY['electronics'];

-- Find products with any of these tags
SELECT * FROM products WHERE tags && ARRAY['sale', 'clearance'];
```

**Example - full-text search:**

```sql
CREATE INDEX idx_fts ON documents USING GIN (to_tsvector('english', content));

SELECT * FROM documents
WHERE to_tsvector('english', content) @@ to_tsquery('english', 'postgresql & performance');
```

**Example - JSONB:**

```sql
CREATE TABLE events (id int, data jsonb);
CREATE INDEX idx_data ON events USING GIN (data);

-- Key exists
SELECT * FROM events WHERE data ? 'user_id';

-- Key-value match
SELECT * FROM events WHERE data @> '{"status": "completed"}';

-- Path query
SELECT * FROM events WHERE data @@ '$.event.type == "click"';
```

**GIN build modes:**

```sql
-- Fast build (default): uses less maintenance_work_mem
CREATE INDEX idx_gin ON table USING GIN (column);

-- With fastupdate (maintains pending list for inserts)
CREATE INDEX idx_gin ON table USING GIN (column)
  WITH (fastupdate = on);
```

**Pending list:**

GIN can batch index updates in a pending list:

```
New insertions → [Pending List]
                      ↓
                (periodically merged into main index)
```

Improves insertion speed but slows queries (must check pending list).

**Configuration:**

```sql
-- Set pending list size
ALTER INDEX idx_gin SET (fastupdate = on);
ALTER INDEX idx_gin SET (gin_pending_list_limit = 4096); -- KB

-- Disable pending list for faster queries
ALTER INDEX idx_gin SET (fastupdate = off);
```

**GIN vs GiST for full-text:**

| Aspect | GIN | GiST |
|--------|-----|------|
| Index size | Larger (3x heap) | Smaller (same as heap) |
| Build time | Slower | Faster |
| Query speed | Faster | Slower |
| Update speed | Slower | Faster |
| Recommendation | Read-heavy | Write-heavy |

### BRIN (Block Range Index)

**Compact index for large sequential data** (`src/backend/access/brin/`).

**Characteristics:**
- Stores summary info for block ranges
- Extremely compact (1000x smaller than B-tree)
- Only effective for correlated data
- Introduced in PostgreSQL 9.5

**When to use:**
- Large tables with naturally ordered data
- Time-series data (append-only)
- Logging tables
- Data warehouse fact tables
- Any table with strong physical correlation

**Structure:**

```
Block Range 0-127:   [min=1, max=500]
Block Range 128-255: [min=501, max=1000]
Block Range 256-383: [min=1001, max=1500]
...
```

**Example:**

```sql
-- Time-series table (naturally ordered by time)
CREATE TABLE measurements (
  timestamp timestamptz,
  sensor_id int,
  value numeric
);

-- BRIN index (128 pages per range by default)
CREATE INDEX idx_ts ON measurements USING BRIN (timestamp);

-- Query
SELECT * FROM measurements
WHERE timestamp BETWEEN '2025-11-01' AND '2025-11-30';
```

**BRIN scan:**

1. Lookup block ranges overlapping query predicate
2. Scan those block ranges
3. Filter results (index is lossy)

**Example - highly effective:**

```
Table: log entries inserted in timestamp order
Index size: 100 KB
Table size: 100 GB
Ratio: 0.0001%

Query scans only blocks with matching ranges
```

**Example - ineffective:**

```
Table: randomly inserted data (no correlation)
BRIN returns all block ranges → full table scan
B-tree would be much better
```

**Configuration:**

```sql
-- Smaller ranges (better selectivity, larger index)
CREATE INDEX idx_brin ON table USING BRIN (column)
  WITH (pages_per_range = 64);

-- Larger ranges (smaller index, less selective)
CREATE INDEX idx_brin ON table USING BRIN (column)
  WITH (pages_per_range = 256);
```

**BRIN operator classes:**

- **minmax**: Stores min/max values (default)
- **inclusion**: Stores bounding values for geometric types
- **bloom**: Uses bloom filter for equality (PostgreSQL 14+)

**Checking correlation:**

```sql
SELECT attname, correlation
FROM pg_stats
WHERE tablename = 'measurements'
  AND attname = 'timestamp';

-- correlation near 1.0 or -1.0: BRIN very effective
-- correlation near 0.0: BRIN ineffective
```

**BRIN maintenance:**

```sql
-- Summarize new blocks
SELECT brin_summarize_new_values('idx_brin');

-- Rebuild index
REINDEX INDEX idx_brin;
```

**BRIN advantages:**

- Minuscule index size
- Fast index creation
- Minimal maintenance overhead
- Perfect for append-only data

**BRIN limitations:**

- Requires strong physical correlation
- Lossy (must recheck heap)
- Only effective for certain workloads
- Not useful for random access

### Index Comparison Summary

| Index Type | Best For | Size | Build Time | Query Speed | Update Speed |
|------------|----------|------|------------|-------------|--------------|
| **B-tree** | General purpose, ordering | Medium | Medium | Fast | Medium |
| **Hash** | Equality only | Small | Fast | Fast | Medium |
| **GiST** | Geometric, full-text (writes) | Medium | Fast | Medium | Fast |
| **SP-GiST** | Partitioned data, IPs | Small | Medium | Fast | Medium |
| **GIN** | Full-text, arrays, JSONB | Large | Slow | Very Fast | Slow |
| **BRIN** | Sequential/time-series | Tiny | Very Fast | Medium* | Fast |

*BRIN query speed depends on data correlation

### Index Maintenance

**VACUUM and indexes:**

VACUUM cleans up dead index entries:

```sql
VACUUM ANALYZE tablename;
```

**REINDEX:**

Rebuild index from scratch:

```sql
REINDEX INDEX idx_name;
REINDEX TABLE tablename;
REINDEX DATABASE dbname;  -- PostgreSQL 12+
```

Useful for:
- Recovering from index corruption
- Eliminating bloat
- Switching index storage parameters

**CREATE INDEX CONCURRENTLY:**

Build index without blocking writes:

```sql
CREATE INDEX CONCURRENTLY idx_name ON table (column);
```

Process:
1. Create index in "invalid" state
2. Wait for transactions to finish
3. Build index with 2-phase scan
4. Mark index valid

**REINDEX CONCURRENTLY** (PostgreSQL 12+):

```sql
REINDEX INDEX CONCURRENTLY idx_name;
```

**Index bloat:**

```sql
-- Check index bloat
SELECT schemaname, tablename, indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
  idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

### Partial Indexes

Index only subset of table:

```sql
CREATE INDEX idx_active_users ON users (email)
WHERE active = true;
```

Benefits:
- Smaller index
- Faster index operations
- Query must include WHERE clause condition

### Expression Indexes

Index computed expression:

```sql
CREATE INDEX idx_lower_email ON users (lower(email));

-- Query uses index
SELECT * FROM users WHERE lower(email) = 'user@example.com';
```

### Index-Only Scans

When index contains all needed columns:

```sql
CREATE INDEX idx_covering ON orders (customer_id, order_date, total);

-- Index-only scan possible
SELECT order_date, total
FROM orders
WHERE customer_id = 123;
```

Requires:
- All columns in SELECT/WHERE in index
- Pages marked all-visible in visibility map

Check with:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_date, total FROM orders WHERE customer_id = 123;
```

Look for "Index Only Scan" in plan.

## Free Space Map

### Overview

The Free Space Map (FSM) is an auxiliary data structure that tracks available free space in each page of a heap relation. Located in `src/backend/storage/freespace/`, it enables PostgreSQL to efficiently find pages with sufficient space for new tuples without scanning the entire table.

The FSM is stored in a separate fork of the relation file:

```
$PGDATA/base/<database_oid>/<relation_oid>_fsm
```

### Purpose and Benefits

**Without FSM:**

```
INSERT needs 100 bytes
→ Scan every page until finding one with ≥100 bytes free
→ O(N) search time
```

**With FSM:**

```
INSERT needs 100 bytes
→ Query FSM for page with ≥100 bytes
→ O(log N) search time
```

**Benefits:**

1. Fast insertion into tables with free space
2. Reduced table bloat (reuses existing pages)
3. Improves UPDATE performance (especially HOT updates)
4. Essential for large tables

### FSM Structure

The FSM is organized as a **tree of pages**:

```
                    [Root FSM Page]
                    Max free space across all children
                   /        |        \
            [Level 1]   [Level 1]   [Level 1]
            Max for     Max for     Max for
            children    children    children
           /    |    \
    [Leaf] [Leaf] [Leaf] ...
    Max free in heap pages (1 leaf per ~4000 heap pages)
```

**Key characteristics:**

- Each FSM leaf page tracks ~4000 heap pages
- Each entry stores max free space as category (0-255)
- Internal pages store maximum of children
- Tree structure allows efficient search

**Free space categories:**

Free space stored as 1 byte per page:

```c
/* Convert bytes to FSM category (0-255) */
static uint8 fsm_space_needed_to_cat(Size needed)
{
    /* Category represents free space in ~32-byte increments */
    /* 0 = 0-31 bytes, 1 = 32-63 bytes, ..., 255 = 8160-8192 bytes */
}
```

This lossy representation trades precision for compact storage.

### FSM Page Format

FSM pages follow standard page layout with special content:

```c
typedef struct FSMPageData
{
    PageHeaderData pd;  /* Standard page header */

    /* Array of free space categories */
    uint8 fp_nodes[FLEXIBLE_ARRAY_MEMBER];
} FSMPageData;
```

**Constants:**

```c
#define BLCKSZ 8192                    /* Page size */
#define FSM_TREE_DEPTH ((BLCKSZ - 1) / 2)  /* Tree levels on page */
#define SlotsPerFSMPage 4096           /* Heap pages tracked per FSM leaf */
```

### FSM Operations

**Recording free space** (`RecordPageWithFreeSpace`):

```c
void RecordPageWithFreeSpace(Relation rel, BlockNumber heapBlk, Size spaceAvail)
{
    /* Convert space to category */
    uint8 cat = fsm_space_avail_to_cat(spaceAvail);

    /* Update FSM tree */
    fsm_set_avail(rel, heapBlk, cat);
}
```

Called by:
- Heap insert (after adding tuple)
- VACUUM (after reclaiming space)
- Page pruning operations

**Searching for free space** (`GetPageWithFreeSpace`):

```c
BlockNumber GetPageWithFreeSpace(Relation rel, Size spaceNeeded)
{
    /* Convert needed space to category */
    uint8 cat = fsm_space_needed_to_cat(spaceNeeded);

    /* Search FSM tree for page with enough space */
    BlockNumber blk = fsm_search(rel, cat);

    return blk;
}
```

**Search algorithm:**

1. Start at FSM root
2. Find child with max space ≥ requested
3. Descend to that child
4. Repeat until reaching leaf
5. Return heap page number

Time complexity: O(log N) where N is number of heap pages

### FSM Maintenance

**VACUUM updates FSM:**

```c
/* During VACUUM */
for each heap page:
    count free space
    RecordPageWithFreeSpace(page_num, free_space)
```

**Truncating FSM:**

When VACUUM truncates empty pages from end of table:

```c
FreeSpaceMapTruncateRel(rel, nblocks);
```

Removes FSM entries for removed heap pages.

### FSM Visibility

**pg_freespacemap extension:**

```sql
CREATE EXTENSION pg_freespacemap;

-- View free space in a table
SELECT blkno, avail
FROM pg_freespace('tablename')
ORDER BY blkno
LIMIT 20;

-- Aggregate statistics
SELECT
  CASE
    WHEN avail = 0 THEN 'full'
    WHEN avail < 64 THEN 'mostly full'
    WHEN avail < 128 THEN 'half full'
    ELSE 'mostly empty'
  END AS category,
  count(*) AS pages
FROM pg_freespace('tablename')
GROUP BY category;
```

### FSM and Table Bloat

**Scenario: High UPDATE rate**

```
Initial:  Table has 1000 pages, all full
UPDATE:   Creates new tuple versions
          Dead tuples remain until VACUUM
VACUUM:   Reclaims space, updates FSM
INSERT:   Uses FSM to find pages with space (reuses existing pages)
```

**Without proper VACUUM:**

```
Dead tuples accumulate
FSM not updated → INSERTs extend table
Table grows unnecessarily (bloat)
```

**With regular VACUUM:**

```
Dead space reclaimed
FSM updated with free space
INSERTs reuse existing pages
Table size stable
```

### FSM Limitations

**Lossy representation:**

- Only 256 categories for 8KB of space
- Precision: ~32 bytes
- May occasionally return page without enough space
- Fallback: Extend table with new page

**Not crash-safe independently:**

- FSM is a hint, not authoritative
- Inconsistent FSM doesn't cause corruption
- Worst case: slightly inefficient space usage
- VACUUM rebuilds accurate FSM

**Manual FSM repair:**

If FSM becomes inaccurate:

```sql
VACUUM tablename;  -- Rebuilds FSM
```

Or for all tables:

```sql
VACUUM;  -- Database-wide
```

### FSM Performance Impact

**Benefits:**

- O(log N) insertion vs O(N) without FSM
- Reduces table growth
- Enables efficient space reuse

**Overhead:**

- Minimal: ~0.2% storage (1 byte per 4000 heap bytes)
- FSM updates are cheap (just setting a byte)
- Read during INSERT (1-2 FSM page reads)

**Example: 100 GB table**

```
Heap: 100 GB
FSM:  ~25 MB (0.025% overhead)
Visibility Map: ~12.5 MB

Total overhead: ~37.5 MB (0.0375%)
```

### FSM Code Locations

**Core FSM functions** (`src/backend/storage/freespace/freespace.c`):

- `GetPageWithFreeSpace`: Find page with free space
- `RecordPageWithFreeSpace`: Update FSM with page's free space
- `GetRecordedFreeSpace`: Query FSM for page's free space
- `FreeSpaceMapTruncateRel`: Truncate FSM
- `FreeSpaceMapVacuum`: VACUUM FSM itself

**FSM tree operations** (`src/backend/storage/freespace/fsmpage.c`):

- `fsm_search`: Search tree for page with space
- `fsm_set_avail`: Update tree with new free space value
- `fsm_get_avail`: Read free space value

## Visibility Map

### Overview

The Visibility Map (VM) is a bitmap tracking which pages contain only tuples that are visible to all transactions. Located in `src/backend/access/heap/visibilitymap.c`, it serves two critical purposes:

1. **Optimize VACUUM**: Skip pages where all tuples are visible
2. **Enable index-only scans**: Avoid heap fetches when possible

The VM is stored in a separate fork:

```
$PGDATA/base/<database_oid>/<relation_oid>_vm
```

### Structure

The VM is a bitmap with 2 bits per heap page:

```c
#define VISIBILITYMAP_ALL_VISIBLE   0x01  /* All tuples visible */
#define VISIBILITYMAP_ALL_FROZEN    0x02  /* All tuples frozen */
```

**Bit meanings:**

- **ALL_VISIBLE**: All tuples on page are visible to all current and future transactions
- **ALL_FROZEN**: All tuples have been frozen (t_xmin replaced with FrozenTransactionId)

**Storage efficiency:**

```
1 heap page (8 KB) → 2 bits in VM
1 VM page (8 KB) → tracks 32,768 heap pages (256 MB)

VM size ≈ heap size / 32,768
Example: 100 GB table → ~3.2 MB visibility map
```

### When Pages Become All-Visible

A page can be marked all-visible when:

1. All tuples on page are visible to all transactions
2. No in-progress transactions when VACUUM runs
3. VACUUM has verified all tuples

**Process:**

```c
/* During VACUUM */
for each heap page:
    if all tuples visible to all transactions:
        visibilitymap_set(rel, page, ALL_VISIBLE)
```

### When Pages Become Not All-Visible

The bit is cleared when:

1. INSERT adds new tuple (not yet visible to all)
2. UPDATE modifies tuple (creates new version)
3. DELETE marks tuple dead

**Implementation:**

```c
/* During INSERT/UPDATE/DELETE */
visibilitymap_clear(rel, page, VISIBILITYMAP_ALL_VISIBLE);
```

This must be WAL-logged for crash recovery.

### VACUUM Optimization

**Without visibility map:**

```
VACUUM scans every page in table
Large table: hours of work
```

**With visibility map:**

```
VACUUM skips pages marked all-visible
Large mostly-static table: minutes instead of hours
```

**Example:**

```sql
-- Table with 100M rows, 99% unchanging
VACUUM tablename;

-- Without VM: Scan 100M rows
-- With VM: Scan only ~1M changed rows
-- Speedup: 100x
```

**VACUUM strategies:**

```sql
-- Regular VACUUM: skips all-visible pages
VACUUM tablename;

-- Aggressive VACUUM: scans all pages (for freezing)
VACUUM (FREEZE) tablename;

-- Autovacuum with freeze prevention
-- Runs aggressive vacuum when table age approaches autovacuum_freeze_max_age
```

### Index-Only Scans

The VM enables index-only scans:

**Scenario:**

```sql
CREATE INDEX idx_email ON users(email);
SELECT email FROM users WHERE email LIKE 'john%';
```

**Without index-only scan:**

1. Scan index to find matching rows
2. For each row: Fetch heap tuple to check visibility
3. Return email value

**With index-only scan:**

1. Scan index to find matching rows
2. For each row:
   - Check visibility map for page
   - If all-visible: Return value from index (no heap fetch!)
   - If not all-visible: Fetch heap tuple

**Performance impact:**

```
Query: SELECT email FROM users WHERE email LIKE 'john%'

With heap fetches:    1000 index reads + 1000 random heap reads
Index-only scan:      1000 index reads only
Speedup:              ~2x (fewer I/O operations)
```

**Requirements:**

1. All columns in SELECT/WHERE must be in index
2. Pages must be marked all-visible in VM

**Monitoring:**

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT email FROM users WHERE email LIKE 'john%';

-- Look for:
-- Index Only Scan using idx_email
-- Heap Fetches: 0  (ideal)
-- Heap Fetches: 1000  (some pages not all-visible)
```

### Freezing and All-Frozen Bit

**Freezing** prevents XID wraparound:

```c
/* Replace old t_xmin with FrozenTransactionId */
if (TransactionIdPrecedes(tuple->t_xmin, oldest_safe_xid))
{
    tuple->t_xmin = FrozenTransactionId;
    visibilitymap_set(rel, page, ALL_FROZEN);
}
```

**ALL_FROZEN advantages:**

1. **VACUUM can skip even for anti-wraparound**: If all pages are frozen, no wraparound risk
2. **Optimization**: Frozen tuples don't need visibility checks

**Configuration:**

```
vacuum_freeze_min_age = 50000000       # Freeze tuples older than this
vacuum_freeze_table_age = 150000000   # Aggressive vacuum threshold
autovacuum_freeze_max_age = 200000000 # Force vacuum to prevent wraparound
```

### Visibility Map Monitoring

**pg_visibility extension:**

```sql
CREATE EXTENSION pg_visibility;

-- Check VM status
SELECT blkno, all_visible, all_frozen
FROM pg_visibility_map('tablename')
LIMIT 20;

-- Summary statistics
SELECT
  count(*) FILTER (WHERE all_visible) AS all_visible_pages,
  count(*) FILTER (WHERE all_frozen) AS all_frozen_pages,
  count(*) AS total_pages,
  round(100.0 * count(*) FILTER (WHERE all_visible) / count(*), 1)
    AS pct_visible
FROM pg_visibility_map('tablename');
```

**Checking VM effectiveness:**

```sql
-- Table with good VM coverage (mostly all-visible)
SELECT relname, n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_live_tup DESC;

-- If many dead tuples: VACUUM needed to set VM bits
-- If recent vacuum: VM should have good coverage
```

### VM and WAL

VM updates are WAL-logged:

**Setting all-visible:**

```c
/* VACUUM marks page all-visible */
START_CRIT_SECTION();
visibilitymap_set(rel, page, ALL_VISIBLE);
/* WAL record written */
END_CRIT_SECTION();
```

**Clearing all-visible:**

```c
/* INSERT/UPDATE/DELETE clears bit */
START_CRIT_SECTION();
visibilitymap_clear(rel, page, ALL_VISIBLE);
/* WAL record written */
END_CRIT_SECTION();
```

This ensures VM is correctly recovered after crash.

### VM File Format

VM pages follow standard page layout:

```c
typedef struct
{
    PageHeaderData pd;  /* Standard page header */

    /* Bitmap data: 2 bits per heap page */
    uint8 bits[FLEXIBLE_ARRAY_MEMBER];
} VMPageData;
```

Each byte stores 4 heap pages (2 bits each):

```
Byte:    [76][54][32][10]
         ↑   ↑   ↑   ↑
         Heap pages 3,2,1,0

Bits: [Frozen][Visible]
```

### VM Performance Impact

**Benefits:**

- **VACUUM**: Massive speedup (skip most pages on read-heavy tables)
- **Index-only scans**: Avoid heap fetches (2x or more speedup)
- **Tiny overhead**: 2 bits per 8KB page (0.003% storage)

**Costs:**

- **Minimal**: VM updates are simple bit operations
- **WAL overhead**: Small WAL records for set/clear operations
- **Slight overhead on writes**: Clear VM bit on UPDATE/DELETE

**Example: 100 GB table**

```
Heap: 100 GB
VM:   ~3 MB (0.003% overhead)

Benefits:
- VACUUM: Hours → Minutes
- Index-only scans: 2x faster
- Wraparound prevention
```

### VM Corruption Recovery

VM is a hint structure - inconsistencies don't corrupt data:

**Incorrect all-visible bit:**

- **Set but shouldn't be**: Index-only scan may return wrong results
- **Clear but should be set**: Just inefficiency, no corruption

**Recovery:**

```sql
-- Force VM rebuild
VACUUM tablename;

-- Or for severe issues
REINDEX TABLE tablename;
VACUUM FREEZE tablename;
```

**Prevention:**

- Keep `data_checksums` enabled
- Regular backups
- Monitor for I/O errors

## TOAST

### Overview

TOAST (The Oversized-Attribute Storage Technique) is PostgreSQL's mechanism for storing large attribute values that don't fit in a normal page. Defined in `src/backend/access/common/toast*.c` and `src/include/access/toast*.h`, TOAST transparently handles values larger than ~2KB.

Without TOAST, PostgreSQL's maximum tuple size would be limited by the 8KB page size, severely restricting column values.

### The Problem TOAST Solves

**Page size limitation:**

```
Page size: 8192 bytes
Page header: ~24 bytes
Item pointers: ~4 bytes each
Tuple header: ~23 bytes
Maximum tuple size: ~8000 bytes

Problem: What about 100KB text column? 10MB bytea value?
```

**TOAST solution:**

Large values stored externally in a TOAST table, with pointer in main table.

### TOAST Strategies

PostgreSQL applies four storage strategies based on column type and size:

```c
#define TOAST_PLAIN_STORAGE       'p'  /* No TOAST, fixed-length */
#define TOAST_EXTERNAL_STORAGE    'e'  /* External storage, no compression */
#define TOAST_EXTENDED_STORAGE    'x'  /* External storage, compression allowed */
#define TOAST_MAIN_STORAGE        'm'  /* Inline, compression allowed */
```

**Strategy details:**

**PLAIN** (`p`):
- Fixed-length types (int, float, etc.)
- Never compressed or moved to TOAST table
- Always stored inline

**EXTENDED** (`x`) - default for most varlena types:
- Try compression first
- If still large, move to TOAST table
- Used for: text, bytea, jsonb, arrays

**EXTERNAL** (`e`):
- Never compress
- Move to TOAST table if large
- Used for large objects that compress poorly
- Example: already-compressed data

**MAIN** (`m`):
- Prefer inline storage
- Try compression
- Move to TOAST table only as last resort
- Used for: shorter text columns that benefit from inline storage

### TOAST Threshold

Values are TOASTed when:

```c
#define TOAST_TUPLE_THRESHOLD 2000  /* ~2KB */
```

**Process:**

1. Try to fit tuple in page
2. If tuple > 2KB:
   - Try compressing EXTENDED columns
   - If still too large, move largest EXTENDED/EXTERNAL columns to TOAST table
   - Repeat until tuple fits or all movable columns moved

### TOAST Table Structure

Each table with TOASTable columns has a TOAST table:

```
Main table: $PGDATA/base/<db>/<relation_oid>
TOAST table: $PGDATA/base/<db>/<toast_relation_oid>
TOAST index: $PGDATA/base/<db>/<toast_index_oid>
```

**TOAST table schema:**

```c
CREATE TABLE pg_toast.pg_toast_<oid> (
    chunk_id    oid,      /* Unique ID for this TOASTed value */
    chunk_seq   int4,     /* Chunk sequence number (0, 1, 2, ...) */
    chunk_data  bytea     /* Actual data chunk (~2000 bytes) */
);

CREATE INDEX pg_toast_<oid>_index ON pg_toast.pg_toast_<oid>
    (chunk_id, chunk_seq);
```

**Example: Large text value**

```
Main table:
+----+------------------------+
| id | description (TOAST ptr)|  ← Points to chunk_id in TOAST table
+----+------------------------+
| 1  | 0x12345678            |
+----+------------------------+

TOAST table (pg_toast.pg_toast_12345):
+-----------+-----------+----------------+
| chunk_id  | chunk_seq | chunk_data     |
+-----------+-----------+----------------+
| 12345678  |    0      | [2000 bytes]   |
| 12345678  |    1      | [2000 bytes]   |
| 12345678  |    2      | [1500 bytes]   |
+-----------+-----------+----------------+
```

Total value size: 5500 bytes, stored in 3 chunks.

### TOAST Pointers

In-line TOAST pointer structure:

```c
typedef struct varattrib_1b_e
{
    uint8 va_header;        /* Header: 1 byte, indicates TOAST */
    uint8 va_tag;           /* TOAST type */

    union {
        struct {
            int32 rawsize;       /* Original uncompressed size */
            int32 extsize;       /* External storage size */
            Oid   valueid;       /* OID in TOAST table */
            Oid   toastrelid;    /* TOAST table OID */
        } indirect;

        /* Or for short compressed values stored inline: */
        uint8 data[FLEXIBLE_ARRAY_MEMBER];  /* Compressed data */
    } va_data;
} varattrib_1b_e;
```

**TOAST pointer types:**

1. **External uncompressed**: Data in TOAST table, not compressed
2. **External compressed**: Data in TOAST table, compressed
3. **Inline compressed**: Compressed data stored inline (< ~2KB)
4. **Indirect**: Pointer to data in another tuple (rare)

### Compression

TOAST uses **pglz** (PostgreSQL LZ) compression:

```c
/* Try to compress attribute */
int32 pglz_compress(const char *source, int32 slen,
                    char *dest, const PGLZ_Strategy *strategy);
```

**Compression decision:**

```c
#define PGLZ_MIN_COMPRESS_RATIO  0.75  /* Must save at least 25% */

if (compressed_size < original_size * 0.75)
    use compressed version
else
    use uncompressed version
```

**Compression is applied to:**
- EXTENDED storage columns
- MAIN storage columns (if needed)
- Skipped for EXTERNAL and PLAIN

**Configuration:**

```sql
-- Change storage strategy for a column
ALTER TABLE mytable
ALTER COLUMN description SET STORAGE EXTERNAL;  -- No compression

ALTER TABLE mytable
ALTER COLUMN data SET STORAGE MAIN;  -- Prefer inline
```

### TOAST Operations

**Insertion:**

```c
/* Insert large tuple */
heap_insert(rel, tuple, ...)
    ↓
toast_insert_or_update(rel, tuple, ...)
    ↓
    if (tuple too large)
        toast_compress_datum(...)      /* Try compression */
        if (still too large)
            toast_save_datum(...)      /* Move to TOAST table */
```

**Retrieval:**

```c
/* Fetch attribute */
heap_getnext(...)
    ↓
    if (attribute is TOASTed)
        toast_fetch_datum(...)
            ↓
            Read TOAST chunks
            Decompress if needed
            Return assembled value
```

**Update:**

```c
/* Update with TOASTed column */
heap_update(rel, oldtup, newtup, ...)
    ↓
    toast_insert_or_update(...)
        ↓
        if (new value same as old)
            Reuse old TOAST pointer (no copy!)
        else
            Delete old TOAST chunks
            Insert new TOAST chunks
```

**Delete:**

```c
/* Delete tuple with TOASTed values */
heap_delete(rel, tid, ...)
    ↓
    (TOAST chunks marked dead via dependency)
    ↓
    VACUUM removes dead TOAST chunks
```

### TOAST and VACUUM

VACUUM cleans up orphaned TOAST chunks:

```
1. VACUUM main table
2. Mark dead tuples' TOAST chunks as dead
3. VACUUM TOAST table
4. Reclaim space from dead chunks
```

**TOAST table bloat:**

High UPDATE rate on TOASTed columns can cause TOAST bloat:

```sql
-- Check TOAST table size
SELECT relname,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size,
       pg_size_pretty(pg_relation_size(oid)) AS main_size,
       pg_size_pretty(pg_total_relation_size(reltoastrelid)) AS toast_size
FROM pg_class
WHERE relname = 'mytable';

-- VACUUM both main and TOAST
VACUUM ANALYZE mytable;
```

### TOAST Performance Implications

**Advantages:**
- Enables large column values
- Automatic and transparent
- Efficient compression saves space
- Unchanged values reuse TOAST pointers

**Costs:**
- Extra I/O for TOASTed column access
- Compression CPU overhead
- TOAST table and index overhead
- Potential bloat with high UPDATE rate

**Performance tips:**

```sql
-- Avoid fetching TOASTed columns unnecessarily
SELECT id, small_column        -- Good: doesn't fetch large_text
FROM mytable
WHERE id = 123;

SELECT *                       -- Bad: fetches all TOAST values
FROM mytable
WHERE id = 123;

-- Use appropriate storage strategy
ALTER TABLE logs
ALTER COLUMN compressed_data SET STORAGE EXTERNAL;  -- Already compressed

-- Consider splitting large columns to separate table
CREATE TABLE documents (
    id serial PRIMARY KEY,
    title text,
    created_at timestamp
);

CREATE TABLE document_content (
    document_id int PRIMARY KEY REFERENCES documents(id),
    content text  -- Large, rarely accessed
);
```

### TOAST Monitoring

```sql
-- Find tables with TOAST tables
SELECT c.relname AS table_name,
       t.relname AS toast_table,
       pg_size_pretty(pg_relation_size(t.oid)) AS toast_size
FROM pg_class c
LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relkind = 'r'
  AND t.relname IS NOT NULL
ORDER BY pg_relation_size(t.oid) DESC;

-- Check TOAST statistics
SELECT schemaname, relname, n_tup_ins, n_tup_upd, n_tup_del
FROM pg_stat_user_tables
WHERE relname LIKE 'pg_toast%'
ORDER BY n_tup_upd DESC;
```

### TOAST Limitations

**Maximum value size:**

```
Maximum TOAST value: 1GB
(due to 30-bit length field in varlena header)

For larger values: Use large objects (lo_*) API
```

**Chunk size:**

```c
#define TOAST_MAX_CHUNK_SIZE  2000  /* ~2KB per chunk */
```

Retrieving 1GB value requires reading 500,000+ chunks (slow).

**Fixed overhead:**

Every TOASTed value incurs:
- TOAST table storage
- Index entry
- Multiple I/O operations

For small values (< 2KB), overhead exceeds benefit.

### TOAST and Logical Replication

TOAST values replicated efficiently:

```
If TOAST pointer unchanged → Send pointer only
If TOAST value changed → Send full new value
```

Logical replication protocols handle TOAST transparently.

### TOAST Code Locations

**Core TOAST functions** (`src/backend/access/common/`):

- `toast_insert_or_update`: Main entry point for TOASTing
- `toast_flatten_tuple`: Expand all TOASTed attributes
- `toast_compress_datum`: Compress attribute
- `toast_save_datum`: Save to TOAST table
- `toast_fetch_datum`: Retrieve from TOAST table
- `toast_delete_datum`: Delete TOAST chunks

## Conclusion

### Summary

The PostgreSQL storage layer is a sophisticated system that provides reliability, performance, and flexibility through carefully designed components working in concert:

1. **Page Structure**: The 8KB slotted page design provides efficient storage for variable-length tuples while maintaining stable tuple identifiers through item pointer indirection.

2. **Buffer Manager**: Multi-level caching with the clock sweep algorithm, coordinated with WAL, ensures high performance while maintaining crash safety.

3. **Heap Access Method**: Unordered tuple storage with support for MVCC, HOT updates, and tuple locking provides the foundation for PostgreSQL's default table storage.

4. **Write-Ahead Logging**: The WAL-before-data protocol guarantees crash recovery, enables point-in-time recovery, and forms the basis for physical replication.

5. **MVCC**: Multi-version concurrency control allows readers and writers to operate without blocking each other, providing high concurrency and multiple isolation levels.

6. **Index Access Methods**: Six specialized index types (B-tree, Hash, GiST, SP-GiST, GIN, BRIN) support diverse query patterns and data types, from general-purpose B-trees to specialized GIN indexes for full-text search.

7. **Free Space Map**: Efficient tracking of available space enables fast insertion and space reuse, preventing unnecessary table growth.

8. **Visibility Map**: Bitmap tracking of all-visible pages dramatically accelerates VACUUM and enables index-only scans.

9. **TOAST**: Transparent handling of large attribute values removes practical limits on column sizes while maintaining reasonable performance.

### Architectural Principles

Several key principles unify these components:

**Reliability First**: Every component prioritizes data integrity and crash safety. WAL protects all modifications, checksums detect corruption, and MVCC ensures consistent snapshots.

**Performance Through Design**: Rather than relying solely on raw speed, PostgreSQL achieves performance through intelligent design: slotted pages enable HOT updates, the buffer manager transforms random I/O into sequential writes, and the visibility map allows massive VACUUM speedups.

**Extensibility**: The access method API, custom index types, and pluggable storage engines demonstrate PostgreSQL's commitment to extensibility without compromising core functionality.

**Transparency**: Complex mechanisms like TOAST, MVCC, and buffer management operate transparently to applications, simplifying development while providing sophisticated features.

### Performance Tuning Summary

Key configuration parameters for storage layer performance:

```
# Buffer management
shared_buffers = 8GB              # 25% of RAM (up to 16GB)
effective_cache_size = 24GB       # Total cache (OS + PostgreSQL)

# WAL configuration
wal_buffers = 16MB
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
max_wal_size = 2GB

# VACUUM tuning
autovacuum = on
autovacuum_naptime = 1min
autovacuum_vacuum_scale_factor = 0.1
vacuum_cost_limit = 2000

# Table storage
default_fillfactor = 90           # For frequently updated tables
```

### Monitoring Essentials

Critical metrics to monitor:

```sql
-- Cache hit ratio (target > 99%)
SELECT sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0)
FROM pg_statio_user_tables;

-- Table bloat
SELECT schemaname, tablename, n_dead_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup, 0), 3) AS dead_ratio
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- WAL generation
SELECT pg_size_pretty(wal_bytes) FROM pg_stat_wal;

-- Index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexrelname !~ '^pg_';
```

### Looking Forward

The storage layer continues to evolve:

- **Pluggable Storage**: PostgreSQL 12+ allows alternative table storage methods
- **Compression**: Built-in table compression (PostgreSQL 14+)
- **I/O Improvements**: Direct I/O, asynchronous I/O enhancements
- **VACUUM Improvements**: Faster and more efficient dead tuple removal
- **Index Enhancements**: Deduplication, better BRIN operator classes
- **Sharding and Partitioning**: Native table partitioning improvements

### Cross-References

Related chapters in this encyclopedia:

- **Chapter 3: Architecture Overview** - How storage fits into PostgreSQL's overall architecture
- **Chapter 5: Query Processing** - How the query executor uses the storage layer
- **Chapter 6: Transactions** - Transaction management and MVCC implementation details
- **Chapter 7: Replication** - How WAL enables physical and logical replication
- **Chapter 10: Internals** - Deep dives into specific subsystems

### Further Reading

**Source code files**:
- `src/backend/storage/buffer/bufmgr.c` - Buffer manager (7,468 lines)
- `src/backend/access/heap/heapam.c` - Heap access method (9,337 lines)
- `src/backend/access/transam/xlog.c` - WAL implementation (9,584 lines)
- `src/backend/access/nbtree/nbtree.c` - B-tree implementation
- `src/backend/storage/freespace/freespace.c` - Free Space Map
- `src/backend/access/heap/visibilitymap.c` - Visibility Map
- `src/backend/access/common/toast*.c` - TOAST implementation

**Documentation**:
- PostgreSQL Documentation: Chapter 73 (Database Physical Storage)
- PostgreSQL Documentation: Chapter 30 (Reliability and the Write-Ahead Log)
- PostgreSQL Wiki: Heap Pageinspect
- Source code comments (extensive and well-maintained)

The PostgreSQL storage layer represents decades of evolution, incorporating lessons from both academic research and production deployment at massive scale. Understanding these components provides essential insight into how PostgreSQL achieves its combination of reliability, performance, and functionality.
