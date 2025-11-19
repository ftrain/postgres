# Chapter 3: Transaction Management

## Overview

PostgreSQL's transaction management system is a sophisticated infrastructure that ensures data consistency, isolation, and durability while supporting high concurrency. At its core, the system implements ACID properties through a combination of Multi-Version Concurrency Control (MVCC), a hierarchical locking system, and Write-Ahead Logging (WAL).

The transaction system is primarily implemented in:
- `src/backend/access/transam/xact.c` - Core transaction management
- `src/backend/storage/lmgr/` - Lock management subsystem
- `src/backend/access/transam/clog.c` - Commit log
- `src/backend/storage/ipc/procarray.c` - Process array management

## 1. ACID Properties Implementation

### 1.1 Atomicity

Atomicity ensures that transactions are all-or-nothing. PostgreSQL implements atomicity through:

**Write-Ahead Logging (WAL)**: All changes are logged before being applied to data pages. On abort, the system simply doesn't replay the changes. On crash recovery, incomplete transactions are rolled back.

**Transaction State Tracking**: Each transaction maintains state in shared memory through the PGPROC structure and tracks all modified resources.

### 1.2 Consistency

Consistency is enforced through:
- Constraint checking at appropriate times during transaction execution
- Deferred constraint validation (when requested)
- Trigger execution to maintain application-level invariants

### 1.3 Isolation

Isolation is implemented through MVCC and four standard SQL isolation levels:
- **READ UNCOMMITTED** (treated as READ COMMITTED in PostgreSQL)
- **READ COMMITTED** (default)
- **REPEATABLE READ**
- **SERIALIZABLE** (with Serializable Snapshot Isolation)

Defined in `src/include/access/xact.h:36-39`:
```c
#define XACT_READ_UNCOMMITTED	0
#define XACT_READ_COMMITTED		1
#define XACT_REPEATABLE_READ	2
#define XACT_SERIALIZABLE		3
```

### 1.4 Durability

Durability is guaranteed through:
- **WAL**: Changes are written to durable storage before commit acknowledgment
- **Synchronous commit levels**: Configurable via `synchronous_commit` GUC
- **Checkpointing**: Periodic flushing of dirty pages to disk

The synchronous commit levels (`src/include/access/xact.h:69-78`):
```c
typedef enum {
    SYNCHRONOUS_COMMIT_OFF,              /* asynchronous commit */
    SYNCHRONOUS_COMMIT_LOCAL_FLUSH,      /* wait for local flush only */
    SYNCHRONOUS_COMMIT_REMOTE_WRITE,     /* wait for local flush and remote write */
    SYNCHRONOUS_COMMIT_REMOTE_FLUSH,     /* wait for local and remote flush */
    SYNCHRONOUS_COMMIT_REMOTE_APPLY,     /* wait for local/remote flush and apply */
} SyncCommitLevel;
```

## 2. Multi-Version Concurrency Control (MVCC)

### 2.1 Overview

MVCC allows readers to access data without blocking writers and vice versa. Each transaction sees a consistent snapshot of the database as it existed at the start of the transaction (or statement, depending on isolation level).

### 2.2 Transaction IDs (XIDs)

Transaction IDs are 32-bit unsigned integers defined in `src/include/access/transam.h:31-35`:

```c
#define InvalidTransactionId        ((TransactionId) 0)
#define BootstrapTransactionId      ((TransactionId) 1)
#define FrozenTransactionId         ((TransactionId) 2)
#define FirstNormalTransactionId    ((TransactionId) 3)
#define MaxTransactionId            ((TransactionId) 0xFFFFFFFF)
```

**FullTransactionId**: To handle XID wraparound, PostgreSQL internally uses 64-bit transaction IDs that combine a 32-bit epoch with the 32-bit XID (`src/include/access/transam.h:65-68`):

```c
typedef struct FullTransactionId {
    uint64  value;  /* epoch in upper 32 bits, xid in lower 32 bits */
} FullTransactionId;
```

### 2.3 SnapshotData Structure

Snapshots determine which tuple versions are visible to a transaction. The core snapshot structure is defined in `src/include/utils/snapshot.h:138-210`:

```c
typedef struct SnapshotData {
    SnapshotType snapshot_type;  /* type of snapshot */

    /* MVCC snapshot fields */
    TransactionId xmin;          /* all XID < xmin are visible to me */
    TransactionId xmax;          /* all XID >= xmax are invisible to me */

    /* Array of in-progress transaction IDs */
    TransactionId *xip;
    uint32        xcnt;          /* # of xact ids in xip[] */

    /* Array of in-progress subtransaction IDs */
    TransactionId *subxip;
    int32         subxcnt;       /* # of xact ids in subxip[] */
    bool          suboverflowed; /* has the subxip array overflowed? */

    bool          takenDuringRecovery;  /* recovery-shaped snapshot? */
    bool          copied;               /* false if it's a static snapshot */

    CommandId     curcid;        /* in my xact, CID < curcid are visible */

    /* For HeapTupleSatisfiesDirty */
    uint32        speculativeToken;

    /* For SNAPSHOT_NON_VACUUMABLE */
    struct GlobalVisState *vistest;

    /* Reference counting for snapshot management */
    uint32        active_count;  /* refcount on ActiveSnapshot stack */
    uint32        regd_count;    /* refcount on RegisteredSnapshots */
    pairingheap_node ph_node;    /* link in RegisteredSnapshots heap */

    /* Transaction completion count for snapshot optimization */
    uint64        snapXactCompletionCount;
} SnapshotData;
```

### 2.4 Snapshot Types

PostgreSQL supports multiple snapshot types (`src/include/utils/snapshot.h:31-115`):

- **SNAPSHOT_MVCC**: Standard MVCC snapshot for transaction isolation
- **SNAPSHOT_SELF**: See own uncommitted changes
- **SNAPSHOT_ANY**: See all tuples regardless of visibility
- **SNAPSHOT_TOAST**: Special snapshot for TOAST data
- **SNAPSHOT_DIRTY**: See uncommitted changes from other transactions
- **SNAPSHOT_HISTORIC_MVCC**: For logical decoding
- **SNAPSHOT_NON_VACUUMABLE**: For determining vacuumability

### 2.5 Visibility Determination

Tuple visibility is determined by comparing the tuple's `xmin` (inserting XID) and `xmax` (deleting XID) against the snapshot:

1. If `xmin >= xmax`, the tuple was inserted but not yet committed when snapshot was taken → invisible
2. If `xmin` is in the snapshot's `xip` array → in-progress → invisible
3. If `xmax` is committed and `xmax < xmax` → deleted → invisible
4. Otherwise → visible

The logic is implemented in `src/backend/access/heap/heapam_visibility.c`.

### 2.6 Snapshot Acquisition

Snapshots are acquired through `GetSnapshotData()` in `src/backend/storage/ipc/procarray.c`. The function:

1. Acquires `ProcArrayLock` in shared mode
2. Records current `nextXid` as snapshot's `xmax`
3. Scans the process array to collect in-progress XIDs
4. Determines oldest in-progress XID as snapshot's `xmin`
5. Releases the lock

## 3. Process Control Structure (PGPROC)

Each backend maintains a PGPROC structure in shared memory. This is the central data structure for transaction and lock management, defined in `src/include/storage/proc.h:184-330`:

```c
struct PGPROC {
    dlist_node    links;              /* list link if process is in a list */
    dlist_head   *procgloballist;     /* procglobal list that owns this PGPROC */

    PGSemaphore   sem;                /* ONE semaphore to sleep on */
    ProcWaitStatus waitStatus;
    Latch         procLatch;          /* generic latch for process */

    /* Transaction ID information */
    TransactionId xid;                /* current top-level XID, or InvalidTransactionId */
    TransactionId xmin;               /* minimal running XID when we started */

    int           pid;                /* Backend's process ID; 0 if prepared xact */
    int           pgxactoff;          /* offset into ProcGlobal arrays */

    /* Virtual transaction ID */
    struct {
        ProcNumber        procNumber;
        LocalTransactionId lxid;
    } vxid;

    /* Database and role */
    Oid           databaseId;
    Oid           roleId;
    Oid           tempNamespaceId;

    bool          isRegularBackend;
    bool          recoveryConflictPending;

    /* LWLock waiting info */
    uint8         lwWaiting;          /* see LWLockWaitState */
    uint8         lwWaitMode;         /* lwlock mode being waited for */
    proclist_node lwWaitLink;

    /* Condition variable support */
    proclist_node cvWaitLink;

    /* Heavyweight lock waiting info */
    LOCK         *waitLock;           /* Lock object we're sleeping on */
    PROCLOCK     *waitProcLock;       /* Per-holder info for awaited lock */
    LOCKMODE      waitLockMode;       /* type of lock we're waiting for */
    LOCKMASK      heldLocks;          /* bitmask for lock types already held */
    pg_atomic_uint64 waitStart;       /* time wait started */

    int           delayChkptFlags;    /* for DELAY_CHKPT_* flags */
    uint8         statusFlags;        /* PROC_* flags */

    /* Synchronous replication support */
    XLogRecPtr    waitLSN;            /* waiting for this LSN or higher */
    int           syncRepState;
    dlist_node    syncRepLinks;

    /* Lock lists by partition */
    dlist_head    myProcLocks[NUM_LOCK_PARTITIONS];

    /* Subtransaction cache */
    XidCacheStatus subxidStatus;
    struct XidCache subxids;          /* cache for subtransaction XIDs */

    /* Group XID clearing support */
    bool          procArrayGroupMember;
    pg_atomic_uint32 procArrayGroupNext;
    TransactionId procArrayGroupMemberXid;

    uint32        wait_event_info;

    /* CLOG group update support */
    bool          clogGroupMember;
    pg_atomic_uint32 clogGroupNext;
    TransactionId clogGroupMemberXid;
    XidStatus     clogGroupMemberXidStatus;
    int64         clogGroupMemberPage;
    XLogRecPtr    clogGroupMemberLsn;

    /* Fast-path lock management */
    LWLock        fpInfoLock;
    uint64       *fpLockBits;
    Oid          *fpRelId;
    bool          fpVXIDLock;
    LocalTransactionId fpLocalTransactionId;

    /* Lock group support */
    PGPROC       *lockGroupLeader;
    dlist_head    lockGroupMembers;
    dlist_node    lockGroupLink;
};
```

### 3.1 PROC_HDR and Dense Arrays

The global ProcGlobal structure maintains dense arrays that mirror frequently-accessed PGPROC fields for better cache performance (`src/include/storage/proc.h:391-437`):

```c
typedef struct PROC_HDR {
    PGPROC       *allProcs;           /* Array of all PGPROC structures */
    TransactionId *xids;              /* Mirrored PGPROC.xid array */
    XidCacheStatus *subxidStates;     /* Mirrored PGPROC.subxidStatus */
    uint8        *statusFlags;        /* Mirrored PGPROC.statusFlags */

    uint32        allProcCount;
    dlist_head    freeProcs;
    dlist_head    autovacFreeProcs;
    dlist_head    bgworkerFreeProcs;
    dlist_head    walsenderFreeProcs;

    pg_atomic_uint32 procArrayGroupFirst;
    pg_atomic_uint32 clogGroupFirst;

    ProcNumber    walwriterProc;
    ProcNumber    checkpointerProc;

    int           spins_per_delay;
    int           startupBufferPinWaitBufId;
} PROC_HDR;
```

## 4. Locking System

PostgreSQL implements a three-tier locking hierarchy to balance performance and functionality.

### 4.1 Spinlocks

**Purpose**: Very short-term locks for protecting simple shared memory structures.

**Implementation**: Hardware atomic test-and-set instructions (when available) or semaphore-based fallback.

**File**: `src/include/storage/s_lock.h`, `src/backend/storage/lmgr/s_lock.c`

**Characteristics**:
- Busy-wait (no sleep)
- No deadlock detection
- No automatic release on error
- Hold time: ~tens of instructions
- Timeout: ~60 seconds (error condition)

**Usage**: Protecting simple counters, linked list manipulations, and as building blocks for LWLocks.

**Type definition** (`src/include/storage/spin.h`):
```c
typedef volatile slock_t;  /* platform-specific atomic type */
```

**Never use spinlocks for**:
- Operations requiring kernel calls
- Long computations
- Anything that might error out

### 4.2 Lightweight Locks (LWLocks)

**Purpose**: Efficient locks for shared memory data structures with read/write access patterns.

**File**: `src/backend/storage/lmgr/lwlock.c`, `src/include/storage/lwlock.h`

**Structure** (`src/include/storage/lwlock.h:41-50`):
```c
typedef struct LWLock {
    uint16        tranche;        /* tranche ID */
    pg_atomic_uint32 state;       /* state of exclusive/nonexclusive lockers */
    proclist_head waiters;        /* list of waiting PGPROCs */
#ifdef LOCK_DEBUG
    pg_atomic_uint32 nwaiters;
    struct PGPROC *owner;
#endif
} LWLock;
```

**Lock Modes** (`src/include/storage/lwlock.h:110-117`):
```c
typedef enum LWLockMode {
    LW_EXCLUSIVE,           /* Exclusive access */
    LW_SHARED,              /* Shared (read) access */
    LW_WAIT_UNTIL_FREE,     /* Wait until lock becomes free */
} LWLockMode;
```

**Characteristics**:
- Support shared and exclusive modes
- FIFO wait queue (fair scheduling)
- Automatic release on error (elog recovery)
- Block on semaphore when contended (no busy-wait)
- No deadlock detection
- Fast when uncontended (~dozens of instructions)

**Key LWLocks**:
- `ProcArrayLock`: Protects process array and snapshot acquisition
- `XidGenLock`: Protects XID generation
- `WALInsertLock`: Controls WAL buffer insertion
- `LockMgrLocks`: 16 partitioned locks for heavyweight lock tables
- `BufferMappingLocks`: 128 partitioned locks for buffer pool hash table

**Array Layout** (`src/include/storage/lwlock.h:101-108`):
```c
#define NUM_BUFFER_PARTITIONS  128
#define NUM_LOCK_PARTITIONS  16
#define NUM_PREDICATELOCK_PARTITIONS  16

#define BUFFER_MAPPING_LWLOCK_OFFSET    NUM_INDIVIDUAL_LWLOCKS
#define LOCK_MANAGER_LWLOCK_OFFSET      (BUFFER_MAPPING_LWLOCK_OFFSET + 128)
#define PREDICATELOCK_MANAGER_LWLOCK_OFFSET (LOCK_MANAGER_LWLOCK_OFFSET + 16)
#define NUM_FIXED_LWLOCKS               (PREDICATELOCK_MANAGER_LWLOCK_OFFSET + 16)
```

### 4.3 Heavyweight Locks (Regular Locks)

**Purpose**: Table-driven lock system with deadlock detection for user-visible objects.

**Files**:
- `src/backend/storage/lmgr/lock.c` - Core lock manager
- `src/backend/storage/lmgr/lmgr.c` - High-level interface
- `src/backend/storage/lmgr/deadlock.c` - Deadlock detection

#### 4.3.1 Lock Structure

The LOCK structure represents a lockable object (`src/include/storage/lock.h:310-324`):

```c
typedef struct LOCK {
    /* hash key */
    LOCKTAG       tag;              /* unique identifier of lockable object */

    /* data */
    LOCKMASK      grantMask;        /* bitmask for lock types already granted */
    LOCKMASK      waitMask;         /* bitmask for lock types awaited */
    dlist_head    procLocks;        /* list of PROCLOCK objects */
    dclist_head   waitProcs;        /* list of waiting PGPROC objects */
    int           requested[MAX_LOCKMODES];  /* counts of requested locks */
    int           nRequested;       /* total of requested[] */
    int           granted[MAX_LOCKMODES];    /* counts of granted locks */
    int           nGranted;         /* total of granted[] */
} LOCK;
```

#### 4.3.2 LOCKTAG Structure

LOCKTAG uniquely identifies a lockable object (`src/include/storage/lock.h:166-174`):

```c
typedef struct LOCKTAG {
    uint32  locktag_field1;      /* e.g., database OID */
    uint32  locktag_field2;      /* e.g., relation OID */
    uint32  locktag_field3;      /* e.g., block number */
    uint16  locktag_field4;      /* e.g., tuple offset */
    uint8   locktag_type;        /* see LockTagType enum */
    uint8   locktag_lockmethodid;  /* lockmethod indicator */
} LOCKTAG;
```

**Lock Tag Types** (`src/include/storage/lock.h:137-152`):
- `LOCKTAG_RELATION` - Whole relation
- `LOCKTAG_RELATION_EXTEND` - Right to extend a relation
- `LOCKTAG_DATABASE_FROZEN_IDS` - Database's datfrozenxid
- `LOCKTAG_PAGE` - One page of a relation
- `LOCKTAG_TUPLE` - One physical tuple
- `LOCKTAG_TRANSACTION` - Transaction (for waiting)
- `LOCKTAG_VIRTUALTRANSACTION` - Virtual transaction
- `LOCKTAG_SPECULATIVE_TOKEN` - Speculative insertion
- `LOCKTAG_OBJECT` - Non-relation database object
- `LOCKTAG_ADVISORY` - Advisory user locks

#### 4.3.3 PROCLOCK Structure

PROCLOCK represents a specific backend's hold/wait on a lock (`src/include/storage/lock.h:371-382`):

```c
typedef struct PROCLOCK {
    /* tag */
    PROCLOCKTAG   tag;            /* unique identifier */

    /* data */
    PGPROC       *groupLeader;    /* proc's lock group leader, or proc itself */
    LOCKMASK      holdMask;       /* bitmask for lock types currently held */
    LOCKMASK      releaseMask;    /* bitmask for lock types to be released */
    dlist_node    lockLink;       /* list link in LOCK's list of proclocks */
    dlist_node    procLink;       /* list link in PGPROC's list of proclocks */
} PROCLOCK;
```

#### 4.3.4 Lock Modes

PostgreSQL supports 8 lock modes with different conflict semantics (`src/backend/storage/lmgr/lock.c:65-119`):

```c
/* Lock mode enumeration (in lockdefs.h) */
#define NoLock                      0
#define AccessShareLock             1  /* SELECT */
#define RowShareLock                2  /* SELECT FOR UPDATE/SHARE */
#define RowExclusiveLock            3  /* UPDATE, DELETE, INSERT */
#define ShareUpdateExclusiveLock    4  /* VACUUM, CREATE INDEX CONCURRENTLY */
#define ShareLock                   5  /* CREATE INDEX */
#define ShareRowExclusiveLock       6  /* Rare, like CREATE TRIGGER */
#define ExclusiveLock               7  /* Blocks all but AccessShareLock */
#define AccessExclusiveLock         8  /* ALTER TABLE, DROP TABLE, TRUNCATE */
```

#### 4.3.5 Lock Compatibility Matrix

The conflict table defines which lock modes conflict (`src/backend/storage/lmgr/lock.c:65-105`):

```
                          Current Lock Mode Held
Requested   ┌────────────────────────────────────────────────────────┐
Lock Mode   │ AS  RS  RE  SUE  SH  SRE  EX  AE │
────────────┼────────────────────────────────────────────────────────┤
AS          │  ✓   ✓   ✓   ✓   ✓   ✓   ✓   ✗  │  AccessShare
RS          │  ✓   ✓   ✓   ✓   ✓   ✓   ✗   ✗  │  RowShare
RE          │  ✓   ✓   ✓   ✓   ✗   ✗   ✗   ✗  │  RowExclusive
SUE         │  ✓   ✓   ✓   ✗   ✗   ✗   ✗   ✗  │  ShareUpdateExclusive
SH          │  ✓   ✓   ✗   ✗   ✓   ✗   ✗   ✗  │  Share
SRE         │  ✓   ✓   ✗   ✗   ✗   ✗   ✗   ✗  │  ShareRowExclusive
EX          │  ✓   ✗   ✗   ✗   ✗   ✗   ✗   ✗  │  Exclusive
AE          │  ✗   ✗   ✗   ✗   ✗   ✗   ✗   ✗  │  AccessExclusive
────────────┴────────────────────────────────────────────────────────┘
✓ = Compatible (no conflict)
✗ = Conflicts (must wait)
```

The actual implementation (`src/backend/storage/lmgr/lock.c:65-105`):

```c
static const LOCKMASK LockConflicts[] = {
    0,  /* NoLock */

    /* AccessShareLock */
    LOCKBIT_ON(AccessExclusiveLock),

    /* RowShareLock */
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* RowExclusiveLock */
    LOCKBIT_ON(ShareLock) | LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* ShareUpdateExclusiveLock */
    LOCKBIT_ON(ShareUpdateExclusiveLock) |
    LOCKBIT_ON(ShareLock) | LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* ShareLock */
    LOCKBIT_ON(RowExclusiveLock) | LOCKBIT_ON(ShareUpdateExclusiveLock) |
    LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* ShareRowExclusiveLock */
    LOCKBIT_ON(RowExclusiveLock) | LOCKBIT_ON(ShareUpdateExclusiveLock) |
    LOCKBIT_ON(ShareLock) | LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* ExclusiveLock */
    LOCKBIT_ON(RowShareLock) |
    LOCKBIT_ON(RowExclusiveLock) | LOCKBIT_ON(ShareUpdateExclusiveLock) |
    LOCKBIT_ON(ShareLock) | LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock),

    /* AccessExclusiveLock */
    LOCKBIT_ON(AccessShareLock) | LOCKBIT_ON(RowShareLock) |
    LOCKBIT_ON(RowExclusiveLock) | LOCKBIT_ON(ShareUpdateExclusiveLock) |
    LOCKBIT_ON(ShareLock) | LOCKBIT_ON(ShareRowExclusiveLock) |
    LOCKBIT_ON(ExclusiveLock) | LOCKBIT_ON(AccessExclusiveLock)
};
```

#### 4.3.6 Fast-Path Locking

To reduce contention on lock manager structures, PostgreSQL implements a fast-path for weak locks on relations (`src/backend/storage/lmgr/README`, line 71-76):

**Eligible locks**:
- Use DEFAULT lock method
- Lock database relations (not shared relations)
- Are "weak" locks: AccessShareLock, RowShareLock, or RowExclusiveLock
- Can quickly verify no conflicting locks exist

**Storage**: Locks stored in PGPROC structure's fast-path arrays rather than shared hash tables.

**Limits**: Configurable via `max_locks_per_transaction`, up to 1024 groups × 16 slots/group.

#### 4.3.7 Lock Acquisition Process

When acquiring a heavyweight lock (`LockAcquire()` in `src/backend/storage/lmgr/lock.c`):

1. **Check fast-path**: If eligible, try to acquire via fast-path
2. **Hash the LOCKTAG**: Compute hash to determine partition
3. **Acquire partition LWLock**: Lock the appropriate partition
4. **Check local lock table**: See if already holding this lock locally
5. **Check shared LOCK table**: Look up or create LOCK object
6. **Check conflicts**: Compare requested mode against grantMask
7. **If no conflict**:
   - Increment grant counts
   - Add to PROCLOCK (if needed)
   - Update masks
   - Return success
8. **If conflict**:
   - Add to wait queue
   - Release partition LWLock
   - Sleep on semaphore
   - Wake up when granted or deadlock detected

## 5. Deadlock Detection

**File**: `src/backend/storage/lmgr/deadlock.c`

### 5.1 Algorithm

PostgreSQL uses a **depth-first search** algorithm to detect cycles in the wait-for graph.

**Trigger**: Deadlock detection runs after `deadlock_timeout` milliseconds (default: 1 second) of waiting for a lock.

**Wait-for Graph**:
- Nodes: Processes (PGPROC)
- Edges: Process A → Process B if A is waiting for a lock held by B

### 5.2 Detection Process

The `DeadLockCheck()` function (`src/backend/storage/lmgr/deadlock.c`):

1. **Build wait-for graph**: Scan lock tables to identify all wait relationships
2. **Depth-first search**: Starting from the waiting process, follow edges
3. **Cycle detection**: If we encounter a previously visited process, we have a cycle
4. **Victim selection**: Choose the process with the least work done (lowest XID)
5. **Resolution**: Send error to victim process to abort its transaction

**States** (`src/include/storage/lock.h:509-518`):
```c
typedef enum {
    DS_NOT_YET_CHECKED,           /* no deadlock check has run yet */
    DS_NO_DEADLOCK,               /* no deadlock detected */
    DS_SOFT_DEADLOCK,             /* deadlock avoided by queue rearrangement */
    DS_HARD_DEADLOCK,             /* deadlock, no way out but ERROR */
    DS_BLOCKED_BY_AUTOVACUUM,     /* blocked by autovacuum worker */
} DeadLockState;
```

### 5.3 Soft Deadlocks

Sometimes processes can be reordered in the wait queue to avoid a deadlock without aborting any transaction. This is a "soft deadlock."

### 5.4 Timeout Strategy

The `deadlock_timeout` delay serves two purposes:
1. Avoid expensive deadlock checks for short lock waits
2. Allow time for locks to be released naturally

## 6. Transaction ID Management and Wraparound

### 6.1 The Wraparound Problem

With 32-bit XIDs, PostgreSQL can only represent ~4 billion transactions before wraparound. The system uses modulo-2³² arithmetic for XID comparisons, which creates a 2-billion transaction window.

**The Crisis Point**: Without intervention, old tuples (with XIDs billions in the past) would suddenly appear to be in the future after wraparound.

### 6.2 TransamVariables Structure

Global transaction state is tracked in `TransamVariablesData` (`src/include/access/transam.h:209-255`):

```c
typedef struct TransamVariablesData {
    /* Protected by OidGenLock */
    Oid           nextOid;
    uint32        oidCount;

    /* Protected by XidGenLock */
    FullTransactionId nextXid;      /* next XID to assign */
    TransactionId oldestXid;        /* cluster-wide minimum datfrozenxid */
    TransactionId xidVacLimit;      /* start forcing autovacuums here */
    TransactionId xidWarnLimit;     /* start complaining here */
    TransactionId xidStopLimit;     /* refuse to advance nextXid beyond here */
    TransactionId xidWrapLimit;     /* where the world ends */
    Oid           oldestXidDB;      /* database with minimum datfrozenxid */

    /* Protected by CommitTsLock */
    TransactionId oldestCommitTsXid;
    TransactionId newestCommitTsXid;

    /* Protected by ProcArrayLock */
    FullTransactionId latestCompletedXid;
    uint64        xactCompletionCount;

    /* Protected by XactTruncationLock */
    TransactionId oldestClogXid;    /* oldest it's safe to look up in clog */
} TransamVariablesData;
```

### 6.3 Freezing

**Freezing** is the process of replacing old XIDs with `FrozenTransactionId` (2), marking them as always visible.

**When it happens**:
- During VACUUM when tuple's `xmin` age exceeds `vacuum_freeze_min_age` (default: 50M)
- During aggressive VACUUM (forced by wraparound concerns)
- Always when `xmin` age exceeds `vacuum_freeze_table_age` (default: 150M)

**Mechanism**:
1. VACUUM scans table pages
2. For each tuple with old `xmin`:
   - Set `xmin` to `FrozenTransactionId`
   - Mark page dirty
   - WAL-log the change
3. Update table's `relfrozenxid` in `pg_class`
4. Update database's `datfrozenxid` in `pg_database`

### 6.4 Wraparound Protection

**Thresholds** (measured in XIDs from `oldestXid`):

- **xidVacLimit** (~200M from `oldestXid`): Start forcing autovacuum
- **xidWarnLimit** (~10M later): Begin warning in logs
- **xidStopLimit** (~3M before wraparound): Refuse new XIDs except for vacuum
- **xidWrapLimit**: Absolute wraparound point (shutdown prevention)

**Emergency Mode**: When `xidStopLimit` is reached, the system enters a mode where only superusers can execute commands, and only for vacuum operations.

### 6.5 MultiXact IDs

For tuple locking (e.g., `SELECT FOR SHARE`), PostgreSQL uses MultiXact IDs to represent multiple lockers. These also wrap around and require freezing, managed similarly to regular XIDs.

**Files**:
- `src/backend/access/transam/multixact.c`
- `src/include/access/multixact.h`

## 7. Transaction Commit and Abort

### 7.1 Commit Processing

The commit path (`CommitTransaction()` in `src/backend/access/transam/xact.c`):

1. **Pre-commit phase**:
   - Fire pre-commit callbacks
   - Write WAL for any pending operations
   - Prepare two-phase commit (if applicable)

2. **Write commit record**:
   - Create `xl_xact_commit` WAL record with:
     - Transaction timestamp
     - Dropped relations (to be unlinked)
     - Invalidation messages
     - Subtransaction XIDs
     - Other metadata
   - Insert into WAL buffers
   - Flush to disk (if synchronous commit)

3. **Update CLOG**:
   - Mark transaction as committed in commit log
   - Use group commit optimization when possible

4. **Post-commit cleanup**:
   - Fire commit callbacks
   - Release locks
   - Clean up resource owners
   - Update stats
   - Clear transaction state

### 7.2 Commit Record Structure

From `src/include/access/xact.h:219-300`:

```c
typedef struct xl_xact_commit {
    TimestampTz xact_time;           /* time of commit */
    uint32      xinfo;               /* info flags */
    /* Additional fields appended based on xinfo flags:
     * - xl_xact_dbinfo (if XACT_XINFO_HAS_DBINFO)
     * - xl_xact_subxacts (if XACT_XINFO_HAS_SUBXACTS)
     * - xl_xact_relfilelocators (if XACT_XINFO_HAS_RELFILELOCATORS)
     * - invalidation messages (if XACT_XINFO_HAS_INVALS)
     * - shared inval messages (if XACT_XINFO_HAS_INVALS)
     * - xl_xact_twophase (if XACT_XINFO_HAS_TWOPHASE)
     * - xl_xact_origin (if XACT_XINFO_HAS_ORIGIN)
     */
} xl_xact_commit;
```

### 7.3 Abort Processing

The abort path (`AbortTransaction()` in `src/backend/access/transam/xact.c`):

1. **Cleanup phase**:
   - Undo any incomplete operations
   - Close cursors
   - Abort subtransactions

2. **Write abort record**:
   - Create `xl_xact_abort` WAL record
   - Insert into WAL (async, no flush required)

3. **Update CLOG**:
   - Mark transaction as aborted
   - Mark subtransactions as aborted

4. **Release resources**:
   - Release all locks
   - Clean up memory contexts
   - Reset buffer pins
   - Fire abort callbacks

5. **Reset state**:
   - Clear transaction ID
   - Reset command counter
   - Clean up temporary tables

### 7.4 Commit Log (CLOG)

**File**: `src/backend/access/transam/clog.c`

The commit log is a SLRU (Simple Least-Recently-Used) buffer cache that tracks transaction status.

**Status Values**:
```c
#define TRANSACTION_STATUS_IN_PROGRESS   0x00
#define TRANSACTION_STATUS_COMMITTED     0x01
#define TRANSACTION_STATUS_ABORTED       0x02
#define TRANSACTION_STATUS_SUB_COMMITTED 0x03
```

**Storage**: 2 bits per transaction, organized in 8KB pages (~32K transactions per page)

**Location**: `$PGDATA/pg_xact/` (renamed from `pg_clog` in PostgreSQL 10)

### 7.5 Subtransactions

Subtransactions (savepoints) maintain their own XIDs and can be independently rolled back.

**Nesting**: Up to 64 levels supported

**XID Assignment**: Subtransactions receive XIDs only if they modify database state

**Commit/Abort**:
- Subtransaction commit merges state into parent
- Subtransaction abort reverts just that subtransaction's changes
- Top transaction abort cascades to all subtransactions

**Caching**: Up to 64 subtransaction XIDs cached in PGPROC's `subxids` array

## 8. Two-Phase Commit (2PC)

**Files**:
- `src/backend/access/transam/twophase.c`
- `src/include/access/twophase.h`

### 8.1 Overview

Two-phase commit enables atomic commits across multiple resource managers (typically distributed databases).

**Phases**:
1. **Prepare**: Coordinator asks all participants to prepare
2. **Commit/Abort**: Coordinator tells all participants to commit or abort

### 8.2 Prepared Transactions

**Command**: `PREPARE TRANSACTION 'gid'`

Where `gid` is a globally unique identifier (max 200 characters).

**Prepare Process**:
1. Validate transaction can be prepared:
   - No temp tables accessed
   - No serialization failures
   - Within `max_prepared_xacts` limit

2. Write prepare record to WAL:
   - Transaction's locks
   - Modified files
   - Prepared timestamp
   - GID

3. Create dummy PGPROC:
   - Represents prepared transaction
   - Holds its locks
   - Appears in pg_prepared_xacts

4. Keep state file:
   - Location: `$PGDATA/pg_twophase/`
   - Survives crashes
   - Used for recovery

### 8.3 Commit/Abort Prepared

**Commit**: `COMMIT PREPARED 'gid'`
1. Look up prepared transaction
2. Write commit record
3. Update CLOG
4. Release locks
5. Remove state file

**Abort**: `ROLLBACK PREPARED 'gid'`
1. Look up prepared transaction
2. Write abort record
3. Update CLOG
4. Release locks
5. Remove state file

### 8.4 Recovery of Prepared Transactions

On crash recovery:
1. Read state files from `pg_twophase/`
2. Recreate dummy PGPROCs
3. Re-acquire their locks
4. Wait for explicit COMMIT/ROLLBACK PREPARED

### 8.5 Limitations and Caveats

- Prepared transactions hold locks indefinitely
- Can cause wraparound issues if not resolved
- GID must be unique across the cluster
- `max_prepared_xacts` must be set > 0
- Cannot prepare if transaction accessed temp objects

## 9. Isolation Levels

PostgreSQL implements four SQL standard isolation levels, though READ UNCOMMITTED is treated as READ COMMITTED.

### 9.1 READ COMMITTED

**Default level**: Yes

**Snapshot Scope**: Per-statement

**Mechanism**:
- New snapshot acquired at start of each statement
- Sees all committed changes before statement start
- Different statements in same transaction may see different data

**Anomalies Prevented**:
- Dirty reads (reading uncommitted data)

**Anomalies Permitted**:
- Non-repeatable reads
- Phantom reads
- Serialization anomalies

**Implementation**:
```c
if (XactIsoLevel >= XACT_REPEATABLE_READ)
    /* Use transaction snapshot */
else
    /* Acquire new snapshot for each statement */
```

### 9.2 REPEATABLE READ

**Snapshot Scope**: Per-transaction

**Mechanism**:
- Single snapshot acquired at first statement of transaction
- All statements see same consistent view
- Can't see changes committed after transaction start

**Anomalies Prevented**:
- Dirty reads
- Non-repeatable reads
- Phantom reads (PostgreSQL-specific, stronger than standard)

**Anomalies Permitted**:
- Serialization anomalies

**Implementation**:
```c
if (IsolationUsesXactSnapshot()) {
    /* Use transaction snapshot for all statements */
    snapshot = GetTransactionSnapshot();
}
```

**Update Behavior**:
- If row updated by concurrent transaction, wait for it to commit/abort
- If committed: raise serialization error
- If aborted: proceed with update

### 9.3 SERIALIZABLE

**Snapshot Scope**: Per-transaction (plus predicate locking)

**Mechanism**: Serializable Snapshot Isolation (SSI)
- Uses REPEATABLE READ snapshot
- Plus predicate locks to detect dangerous structures
- Monitors read/write dependencies between transactions

**Anomalies Prevented**:
- All anomalies (guaranteed serializable execution)

**Implementation**: See Section 9.4

### 9.4 Serializable Snapshot Isolation (SSI)

**Files**:
- `src/backend/storage/lmgr/predicate.c`
- `src/backend/storage/lmgr/README-SSI`
- `src/include/storage/predicate.h`

#### 9.4.1 Theory

SSI prevents serialization anomalies by detecting dangerous patterns in the dependency graph between transactions.

**Dependency Types**:
- **rw-dependency** (read-write): T1 reads, T2 writes the same data
- **wr-dependency** (write-read): T1 writes, T2 reads the same data
- **ww-dependency** (write-write): T1 and T2 both write the same data

**Dangerous Structure**: A cycle in the serialization graph containing at least two rw-dependencies with consecutive edges.

**Detection**: If T1 → T2 → T3 → T1 and at least two edges are rw-dependencies, abort one transaction.

#### 9.4.2 Predicate Locks

Unlike heavyweight locks, predicate locks don't block—they only track read patterns.

**Lock Granularity**:
- Tuple-level
- Page-level (if too many tuple locks)
- Relation-level (if too many page locks)

**Lock Promotion**: Automatically promoted to coarser granularity to limit memory usage.

**SIRead Locks**: Special locks that track what was read

**Structure** (conceptual):
```c
typedef struct SERIALIZABLEXACT {
    VirtualTransactionId vxid;
    /* Lists of predicates read/written */
    /* Lists of conflicts (rw-dependencies) */
    /* Flags indicating dangerous structures */
} SERIALIZABLEXACT;
```

#### 9.4.3 Conflict Detection

**On Write**:
1. Check if any concurrent transaction read this data
2. If yes, create rw-conflict edge
3. Check for dangerous structure
4. If found, mark transaction for abort

**On Commit**:
1. Check if transaction is part of dangerous structure
2. If yes, abort with serialization failure
3. Otherwise, commit and cleanup predicate locks

**On Read**:
1. Record predicate lock on read data
2. Check if any concurrent transaction wrote this data
3. Create wr-conflict edge if needed

#### 9.4.4 Safe Snapshots

A transaction can commit safely if:
1. No older active transaction exists, OR
2. It's marked as "safe" (no dangerous structures possible)

**Optimization**: "Deferrable" read-only transactions wait for a safe snapshot before starting, guaranteeing no serialization failures.

#### 9.4.5 Performance Considerations

**Costs**:
- Extra shared memory for predicate locks
- CPU overhead for conflict detection
- Possible serialization failures requiring retry

**Best Practices**:
- Use SERIALIZABLE only when necessary
- Keep transactions short
- Use DEFERRABLE for read-only transactions
- Retry on serialization failures

#### 9.4.6 Configuration

**GUC Variables**:
- `max_pred_locks_per_transaction`: Memory for predicate locks (default: 64)
- `max_pred_locks_per_relation`: Triggers promotion to relation lock (default: -2, auto)
- `max_pred_locks_per_page`: Triggers promotion to page lock (default: 2)

## 10. Subtransaction Management

### 10.1 Savepoints

**SQL Command**: `SAVEPOINT name`

**Purpose**: Create a named point within a transaction to which you can roll back.

**Implementation**:
- Each savepoint starts a new subtransaction
- Receives own SubTransactionId
- May receive XID if it modifies data
- Tracks resource ownership separately

### 10.2 Subtransaction Stack

Subtransactions are organized in a tree:
```
TopTransaction (XID = 1000)
├── Subtransaction 1 (SubXid = 1)
│   ├── Subtransaction 2 (SubXid = 2, XID = 1001)
│   └── Subtransaction 3 (SubXid = 3)
└── Subtransaction 4 (SubXid = 4, XID = 1002)
```

**Current State**: Tracked in `TopTransactionStateData` in `src/backend/access/transam/xact.c`

### 10.3 XID Assignment to Subtransactions

Subtransactions receive XIDs only if they:
- Modify database tables
- Create temp tables
- Acquire certain types of locks

**Optimization**: Read-only subtransactions don't get XIDs

### 10.4 Subtransaction Cache

Each backend caches up to 64 subtransaction XIDs in `PGPROC.subxids` array.

**Overflow**:
- Set `subxidStatus.overflowed = true`
- Must consult `pg_subtrans` for remaining subXIDs
- Performance impact on visibility checks

### 10.5 Commit/Abort Behavior

**RELEASE SAVEPOINT**: Merges subtransaction into parent
- Resources transferred to parent
- Locks retained
- Memory contexts merged

**ROLLBACK TO SAVEPOINT**: Reverts subtransaction
- Releases resources
- Keeps locks (they were acquired by parent or earlier subtransactions)
- Restarts subtransaction at savepoint

**Top Transaction Abort**: Cascades to all subtransactions

## 11. Transaction State Tracking

### 11.1 Transaction State Machine

Transactions progress through states defined in `TransState` enum:

```c
typedef enum TransState {
    TRANS_DEFAULT,      /* Not in transaction */
    TRANS_START,        /* Starting transaction */
    TRANS_INPROGRESS,   /* Inside valid transaction */
    TRANS_COMMIT,       /* Commit in progress */
    TRANS_ABORT,        /* Abort in progress */
    TRANS_PREPARE,      /* Prepare in progress */
} TransState;
```

### 11.2 Transaction Flags

Various flags track transaction properties (`src/include/access/xact.h:97-122`):

```c
#define XACT_FLAGS_ACCESSEDTEMPNAMESPACE     (1U << 0)  /* Used temp objects */
#define XACT_FLAGS_ACQUIREDACCESSEXCLUSIVELOCK (1U << 1) /* Held AEL */
#define XACT_FLAGS_NEEDIMMEDIATECOMMIT       (1U << 2)  /* e.g., CREATE DATABASE */
#define XACT_FLAGS_PIPELINING                (1U << 3)  /* Extended protocol pipeline */
```

### 11.3 Command Counter

**CommandId**: Sequence number within a transaction, incremented for each SQL command.

**Purpose**: Distinguish tuples modified by different commands in same transaction.

**Implementation**:
- `currentCommandId` in transaction state
- Stored in tuple's `t_cid` field (command ID)
- Used by `HeapTupleSatisfiesSelf()` for intra-transaction visibility

## 12. Group Commit Optimization

### 12.1 WAL Insert Locks

Multiple backends can insert WAL records concurrently using multiple `WALInsertLocks`.

**Count**: Configurable, typically 8

**Process**:
1. Backend acquires one of N WAL insert locks
2. Reserves space in WAL buffer
3. Copies record to buffer
4. Releases insert lock

### 12.2 CLOG Group Update

Instead of each backend individually updating CLOG, backends form groups:

**Leader**: First backend to reach commit point
**Members**: Backends that arrive during leader's processing

**Process**:
1. Backend adds itself to group via `procArrayGroupFirst`
2. Leader takes all members' XIDs
3. Leader updates CLOG for entire group
4. Leader wakes up all members
5. Members return to their clients

**Benefit**: Amortizes expensive CLOG I/O across multiple transactions

**File**: `src/backend/access/transam/clog.c` - `TransactionIdSetPageStatusInternal()`

## 13. Performance Considerations

### 13.1 Lock Contention

**Hot Locks**:
- `ProcArrayLock`: Snapshot acquisition, XID assignment
- `WALInsertLocks`: WAL record insertion
- `CLogControlLock`: CLOG updates
- Buffer mapping locks: Buffer pool hash table

**Mitigation Strategies**:
- Partitioning (lock hash tables, buffer mappings)
- Group operations (group commit, group XID clear)
- Lock-free algorithms (atomic operations)
- Fast-path locking

### 13.2 Transaction ID Consumption

**Problem**: Applications doing many small transactions consume XIDs rapidly

**Monitoring**:
```sql
SELECT age(datfrozenxid) FROM pg_database WHERE datname = 'postgres';
```

**Mitigation**:
- Regular vacuuming (aggressive when near limits)
- Batch operations into larger transactions
- Use subtransactions sparingly

### 13.3 Snapshot Scalability

**Issue**: `GetSnapshotData()` must scan entire process array

**Cost**: O(max_connections) per snapshot

**Optimizations**:
- Dense arrays (PROC_HDR) for better cache locality
- `xactCompletionCount` to reuse snapshots when no transactions completed
- `GlobalVisState` for computing visibility horizons

### 13.4 Long-Running Transactions

**Problems**:
- Block VACUUM from cleaning dead tuples (hold back xmin horizon)
- Consume snapshot memory (large `xip` arrays)
- Increase risk of wraparound
- Hold locks for extended periods

**Detection**:
```sql
SELECT pid, xact_start, state, query
FROM pg_stat_activity
WHERE xact_start < now() - interval '1 hour'
ORDER BY xact_start;
```

## 14. Debugging and Monitoring

### 14.1 Lock Monitoring

**System Views**:
- `pg_locks`: Current locks held/awaited
- `pg_stat_activity`: Backend status including wait events
- `pg_blocking_pids(pid)`: PIDs blocking a given backend

**Lock Wait Events**:
- `Lock:relation`, `Lock:tuple`, etc.
- `LWLock:ProcArray`, `LWLock:WALInsert`, etc.

### 14.2 Transaction Information

**Functions**:
- `txid_current()`: Current transaction ID (64-bit)
- `pg_current_xact_id()`: Full transaction ID
- `pg_snapshot_xmin(pg_current_snapshot())`: Snapshot xmin
- `age(xid)`: Age in transactions

**Views**:
- `pg_stat_activity`: Current transaction state
- `pg_prepared_xacts`: Prepared transactions
- `pg_stat_database`: Transaction counts, conflicts

### 14.3 Deadlock Logging

**Configuration**:
```
log_lock_waits = on          # Log long lock waits
deadlock_timeout = 1s        # Time before deadlock check
log_statement = 'all'        # Log all statements (for debugging)
```

**Log Output**: Contains wait-for graph and victim selection.

### 14.4 Trace Flags

**Compile-time Debug Options** (in `src/include/storage/lock.h`):
```c
#ifdef LOCK_DEBUG
extern int Trace_lock_oidmin;
extern bool Trace_locks;
extern bool Trace_userlocks;
extern int Trace_lock_table;
extern bool Debug_deadlocks;
#endif
```

Enable with: `CFLAGS="-DLOCK_DEBUG" ./configure`

## 15. Notable Source Code Locations

### 15.1 Core Transaction Files

| File | Purpose | Key Functions |
|------|---------|---------------|
| `src/backend/access/transam/xact.c` | Transaction management | `StartTransaction()`, `CommitTransaction()`, `AbortTransaction()` |
| `src/backend/access/transam/varsup.c` | XID/OID generation | `GetNewTransactionId()`, `GetNewObjectId()` |
| `src/backend/access/transam/clog.c` | Commit log | `TransactionIdSetTreeStatus()`, `TransactionIdGetStatus()` |
| `src/backend/access/transam/twophase.c` | Two-phase commit | `PrepareTransaction()`, `FinishPreparedTransaction()` |
| `src/backend/access/transam/subtrans.c` | Subtransaction tracking | `SubTransSetParent()`, `SubTransGetParent()` |

### 15.2 Lock Manager Files

| File | Purpose | Key Functions |
|------|---------|---------------|
| `src/backend/storage/lmgr/lock.c` | Heavyweight locks | `LockAcquire()`, `LockRelease()`, `GrantLock()` |
| `src/backend/storage/lmgr/lmgr.c` | Lock manager API | `LockRelation()`, `UnlockRelation()` |
| `src/backend/storage/lmgr/deadlock.c` | Deadlock detection | `DeadLockCheck()`, `DeadLockReport()` |
| `src/backend/storage/lmgr/lwlock.c` | Lightweight locks | `LWLockAcquire()`, `LWLockRelease()` |
| `src/backend/storage/lmgr/s_lock.c` | Spinlocks | `s_lock()`, platform-specific code |
| `src/backend/storage/lmgr/proc.c` | Process/wait queues | `ProcSleep()`, `ProcWakeup()` |
| `src/backend/storage/lmgr/predicate.c` | SSI implementation | `PredicateLockTuple()`, `CheckForSerializableConflictOut()` |

### 15.3 Snapshot and Visibility

| File | Purpose | Key Functions |
|------|---------|---------------|
| `src/backend/storage/ipc/procarray.c` | Process array | `GetSnapshotData()`, `ProcArrayAdd()` |
| `src/backend/utils/time/snapmgr.c` | Snapshot management | `RegisterSnapshot()`, `GetTransactionSnapshot()` |
| `src/backend/access/heap/heapam_visibility.c` | Tuple visibility | `HeapTupleSatisfiesMVCC()`, `HeapTupleSatisfiesUpdate()` |

### 15.4 Key Header Files

| File | Contents |
|------|----------|
| `src/include/access/xact.h` | Transaction state, isolation levels, commit record formats |
| `src/include/access/transam.h` | XID definitions, TransamVariables |
| `src/include/storage/proc.h` | PGPROC structure, PROC_HDR |
| `src/include/storage/lock.h` | LOCK, PROCLOCK, LOCKTAG structures, lock modes |
| `src/include/storage/lwlock.h` | LWLock structure, modes |
| `src/include/utils/snapshot.h` | SnapshotData structure, snapshot types |

## 16. WAL Records for Transactions

Transaction state changes are logged to WAL for crash recovery.

### 16.1 Transaction WAL Record Types

Defined in `src/include/access/xact.h:170-178`:

```c
#define XLOG_XACT_COMMIT            0x00
#define XLOG_XACT_PREPARE           0x10
#define XLOG_XACT_ABORT             0x20
#define XLOG_XACT_COMMIT_PREPARED   0x30
#define XLOG_XACT_ABORT_PREPARED    0x40
#define XLOG_XACT_ASSIGNMENT        0x50  /* Assign XIDs to subtransactions */
#define XLOG_XACT_INVALIDATIONS     0x60
```

### 16.2 Commit Record Contents

A commit record can include (flags in `xinfo` field):
- `XACT_XINFO_HAS_DBINFO`: Database and tablespace OIDs
- `XACT_XINFO_HAS_SUBXACTS`: Array of subtransaction XIDs
- `XACT_XINFO_HAS_RELFILELOCATORS`: Relations to be deleted
- `XACT_XINFO_HAS_INVALS`: Invalidation messages for system caches
- `XACT_XINFO_HAS_TWOPHASE`: Two-phase commit state
- `XACT_XINFO_HAS_ORIGIN`: Replication origin info
- `XACT_XINFO_HAS_AE_LOCKS`: Access Exclusive locks held
- `XACT_XINFO_HAS_GID`: Global transaction ID

### 16.3 Recovery

During crash recovery (`src/backend/access/transam/xlog.c`):

1. **Read WAL** from last checkpoint
2. **Replay records**:
   - Commit records → mark in CLOG as committed
   - Abort records → mark in CLOG as aborted
   - Prepare records → recreate prepared transactions
3. **Undo phase**: Abort any transactions in-progress at crash
4. **Cleanup**: Remove temporary files, reset transaction state

## 17. Advanced Topics

### 17.1 Parallel Query and Transactions

Parallel workers inherit transaction state but:
- Cannot start subtransactions
- Cannot access catalogs (in some contexts)
- Share parent's XID but don't modify transaction state
- Coordinate through shared memory and dynamic shared memory

### 17.2 Logical Replication and Transaction Tracking

Logical decoding requires:
- Historic snapshots (`SNAPSHOT_HISTORIC_MVCC`)
- Replication slots to prevent WAL removal
- Transaction reassembly from WAL stream
- Handling of concurrent transactions

**File**: `src/backend/replication/logical/decode.c`

### 17.3 Hot Standby and Transaction Conflicts

On replicas, replay can conflict with queries:
- **Cleanup conflicts**: VACUUM removes tuples still visible to query
- **Lock conflicts**: Replay needs lock held by query
- **Snapshot conflicts**: Old snapshots block VACUUM replay

**Resolution**:
- Cancel query (after `max_standby_streaming_delay`)
- Delay replay
- Configure `hot_standby_feedback`

**File**: `src/backend/storage/ipc/standby.c`

### 17.4 Prepared Transactions and Replication

Prepared transactions require special handling:
- Must exist on all replicas before COMMIT PREPARED
- Replayed during archive/streaming recovery
- Can span failover events

## 18. Common Pitfalls and Best Practices

### 18.1 Pitfalls

1. **Idle in Transaction**: Holding transaction open without activity
   - Blocks VACUUM
   - Holds locks
   - Consumes connection slot

2. **Long Transactions**:
   - Table bloat
   - Wraparound risk
   - Lock contention

3. **Excessive Subtransactions**:
   - PGPROC subxids cache overflow (> 64)
   - Performance degradation
   - Every operation must check `pg_subtrans`

4. **Forgotten Prepared Transactions**:
   - Locks held indefinitely
   - Wraparound danger
   - Resource leaks

5. **Not Handling Serialization Failures**:
   - SERIALIZABLE requires application retry logic
   - Can lead to user-visible errors

### 18.2 Best Practices

1. **Keep Transactions Short**:
   - Acquire locks late
   - Release early
   - Minimize work in transaction

2. **Use Appropriate Isolation Level**:
   - READ COMMITTED for most workloads
   - REPEATABLE READ for consistent reporting
   - SERIALIZABLE only when needed

3. **Monitor Transaction Age**:
   ```sql
   SELECT datname, age(datfrozenxid)
   FROM pg_database
   ORDER BY age(datfrozenxid) DESC;
   ```

4. **Handle Serialization Failures**:
   ```python
   while True:
       try:
           # Transaction logic
           break
       except SerializationError:
           # Retry with exponential backoff
           time.sleep(retry_delay)
   ```

5. **Vacuum Regularly**:
   - Ensure autovacuum is running
   - Tune `autovacuum_vacuum_cost_limit`
   - Manual VACUUM for critical tables

6. **Set Appropriate Timeouts**:
   ```sql
   SET statement_timeout = '30s';
   SET idle_in_transaction_session_timeout = '5min';
   ```

## 19. Future Directions

### 19.1 Ongoing Work

- **64-bit XIDs**: Eliminate wraparound concerns entirely
- **Improved SSI performance**: Reduce overhead of serializable transactions
- **Better subtransaction handling**: Reduce cache overflow impact
- **Enhanced monitoring**: More visibility into transaction internals

### 19.2 Research Areas

- Lock-free data structures for hot paths
- Improved deadlock prevention (vs. detection)
- Better integration with storage engines
- Optimistic concurrency control alternatives

## Conclusion

PostgreSQL's transaction management system represents decades of refinement in database concurrency control. The combination of MVCC, hierarchical locking, and sophisticated snapshot isolation provides both high performance and strong consistency guarantees. Understanding these mechanisms is essential for:

- **Database Developers**: Implementing new features correctly
- **Application Developers**: Choosing appropriate isolation levels and handling conflicts
- **DBAs**: Monitoring, tuning, and troubleshooting production systems
- **Contributors**: Extending and optimizing the system

The modular design, with clear separation between spinlocks, LWLocks, and heavyweight locks, and the elegant MVCC implementation based on snapshots and visibility rules, demonstrates the careful engineering that makes PostgreSQL a robust and scalable database system.

## References

1. **Source Code Documentation**:
   - `src/backend/storage/lmgr/README` - Locking system overview
   - `src/backend/storage/lmgr/README-SSI` - Serializable Snapshot Isolation
   - `src/backend/access/transam/README` - Transaction system

2. **Academic Papers**:
   - "Serializable Snapshot Isolation in PostgreSQL" - Fekete et al.
   - "A Critique of ANSI SQL Isolation Levels" - Berenson et al.

3. **PostgreSQL Documentation**:
   - Chapter 13: Concurrency Control
   - Chapter 30: Reliability and the Write-Ahead Log

4. **Key Files** (for reference):
   - Transaction: `src/backend/access/transam/xact.c:1-6000`
   - Locking: `src/backend/storage/lmgr/lock.c:1-4500`
   - Snapshots: `src/backend/storage/ipc/procarray.c:1-5000`
   - SSI: `src/backend/storage/lmgr/predicate.c:1-5000`
