-- SQLite does not enforce foreign key constraints by default. 
-- This PRAGMA must be run at the start of every session/connection 
-- (DB Browser, R via RSQLite, etc.) for referential integrity to be enforced. -- It is NOT a permanent setting saved in the database file itself. 

PRAGMA foreign_keys = ON;

-- Policy table: one row per policy, core characteristics at issue
CREATE TABLE Policy (
    policy_id       INTEGER PRIMARY KEY,
    issue_age       INTEGER NOT NULL,
    gender          TEXT NOT NULL CHECK (gender IN ('M', 'F')),
    smoker_status   TEXT NOT NULL CHECK (smoker_status IN ('Smoker', 'Nonsmoker')),
    product_type    TEXT NOT NULL CHECK (product_type IN ('Term', 'Whole Life', 'Deferred Whole Life')),	
    face_amount     REAL NOT NULL,
    term_years      INTEGER,        -- only populated for Term policies
    deferral_years  INTEGER,        -- only populated for Deferred policies
    issue_date      DATE NOT NULL
);

-- Death table: one row per death event
CREATE TABLE Death (
    death_id        INTEGER PRIMARY KEY,
    policy_id       INTEGER NOT NULL,
    death_date      DATE NOT NULL,
    attained_age    INTEGER NOT NULL,
    FOREIGN KEY (policy_id) REFERENCES Policy(policy_id)
);

-- Exposure table: one row per policy per exposure year
CREATE TABLE Exposure (
    exposure_id       INTEGER PRIMARY KEY,
    policy_id         INTEGER NOT NULL,
    exposure_year     INTEGER NOT NULL,
    attained_age      INTEGER NOT NULL,
    exposure_fraction REAL NOT NULL CHECK (exposure_fraction > 0 AND exposure_fraction <= 1),
    in_deferral       BOOLEAN NOT NULL DEFAULT 0,   -- 1 = TRUE, within Deferred policy's waiting period
    FOREIGN KEY (policy_id) REFERENCES Policy(policy_id)
);
