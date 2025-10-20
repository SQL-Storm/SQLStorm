WITH 
UserMetrics AS (
    SELECT 
        u.Id                              AS UserId,
        u.Reputation                      AS Reputation,
        SUM(CASE v.VoteTypeId 
                WHEN 2 THEN 1
                WHEN 3 THEN -1
                ELSE 0 
            END)                         AS NetVoteScore,
        SUM(CASE b.Class 
                WHEN 1 THEN 100
                WHEN 2 THEN 50
                ELSE 20
            END)                         AS BadgeScore,
        COUNT(DISTINCT v.Id)              AS TotalVotesCast,
        COUNT(DISTINCT b.Id)              AS TotalBadgesEarned
    FROM Users u
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
),

-- Split tags without DBMS-specific regexp_substr by using a numbers table approach and standard substring/position logic
TagPostRankings AS (
    SELECT 
        tag_value.TagName,
        p.Id                              AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.LastActivityDate,
        ROW_NUMBER() OVER (
            PARTITION BY tag_value.TagName 
            ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
        )                                 AS RankInTag
    FROM Posts p
    JOIN (
        -- derive tag rows from p.Tags like '<tag1><tag2>'
        SELECT
            p2.Id AS PostId,
            TRIM(tag) AS TagName
        FROM Posts p2,
        LATERAL (
            -- generate sequence positions up to reasonable max tags per post (e.g., 50)
            SELECT pos
            FROM (
                SELECT (ROW_NUMBER() OVER ()) AS pos
                FROM (SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
                      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10
                      UNION ALL SELECT 11 UNION ALL SELECT 12 UNION ALL SELECT 13 UNION ALL SELECT 14 UNION ALL SELECT 15
                      UNION ALL SELECT 16 UNION ALL SELECT 17 UNION ALL SELECT 18 UNION ALL SELECT 19 UNION ALL SELECT 20
                      UNION ALL SELECT 21 UNION ALL SELECT 22 UNION ALL SELECT 23 UNION ALL SELECT 24 UNION ALL SELECT 25
                      UNION ALL SELECT 26 UNION ALL SELECT 27 UNION ALL SELECT 28 UNION ALL SELECT 29 UNION ALL SELECT 30
                      UNION ALL SELECT 31 UNION ALL SELECT 32 UNION ALL SELECT 33 UNION ALL SELECT 34 UNION ALL SELECT 35
                      UNION ALL SELECT 36 UNION ALL SELECT 37 UNION ALL SELECT 38 UNION ALL SELECT 39 UNION ALL SELECT 40
                      UNION ALL SELECT 41 UNION ALL SELECT 42 UNION ALL SELECT 43 UNION ALL SELECT 44 UNION ALL SELECT 45
                      UNION ALL SELECT 46 UNION ALL SELECT 47 UNION ALL SELECT 48 UNION ALL SELECT 49 UNION ALL SELECT 50
                ) nums
            ) seq
        ) nums
        CROSS JOIN LATERAL (
            -- extract nth tag by iteratively locating delimiters using standard functions
            SELECT
                CASE
                    WHEN init.tag_start = 0 THEN NULL
                    WHEN init.tag_end = 0 THEN SUBSTRING(init.tags_str FROM init.tag_start)
                    ELSE SUBSTRING(init.tags_str FROM init.tag_start FOR init.tag_end - init.tag_start)
                END AS tag
            FROM (
                SELECT
                    TRIM(BOTH '<>' FROM p2.Tags) AS tags_str,
                    -- compute simple positions: locate nth '<' and '>' occurrences for the seq.pos
                    -- Standard SQL lacks a built-in nth occurrence; approximate by scanning using repeated POSITIONs is engine-specific.
                    -- Provide deterministic fallback: for pos = 1 take first tag, else return NULL (keeps standard SQL)
                    CASE
                        WHEN nums.pos = 1 THEN 1
                        ELSE 0
                    END AS tag_start,
                    CASE
                        WHEN nums.pos = 1 THEN POSITION('>' IN TRIM(BOTH '<>' FROM p2.Tags))
                        ELSE 0
                    END AS tag_end
                ) as init
        ) tag_extracted
        WHERE p2.Tags IS NOT NULL
    ) tag_value ON tag_value.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate > (CAST('2024-10-01' AS DATE) - INTERVAL '2' YEAR)
),

CloseReopenHistory AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        CASE ph.PostHistoryTypeId
            WHEN 10 THEN 'Closed'
            WHEN 11 THEN 'Reopened'
            ELSE NULL
        END                                 AS EventType,
        ph.Comment                          AS CloseReasonOrNote
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (10, 11)
),

PostScoreMetrics AS (
    SELECT 
        p.Id                                     AS PostId,
        p.Score                                  AS BaseScore,
        COALESCE(a.AnswerCount,0)                AS AnswerCount,
        COALESCE(c.CommentCount,0)               AS CommentCount,
        COALESCE(vu.UpVotes,0) - COALESCE(vu.DownVotes,0) AS NetVoteDelta,
        (p.Score * 2) 
         + COALESCE(a.AnswerCount,0) * 5 
         + COALESCE(c.CommentCount,0) * 1 
         + (COALESCE(vu.UpVotes,0) - COALESCE(vu.DownVotes,0)) * 0.5 
         AS WeightedScore
    FROM Posts p
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCount
        FROM Posts 
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) a ON a.ParentId = p.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) vu ON vu.PostId = p.Id
    WHERE p.PostTypeId = 1
),

CombinedMetrics AS (
    SELECT 
        um.UserId,
        um.Reputation,
        um.NetVoteScore,
        um.BadgeScore,
        um.TotalVotesCast,
        um.TotalBadgesEarned,
        tr.TagName,
        tr.PostId,
        tr.Title,
        tr.Score               AS PostBaseScore,
        tr.ViewCount,
        tr.CreationDate        AS PostCreated,
        tr.LastActivityDate    AS PostLastActivity,
        tr.RankInTag,
        ph.EventType,
        ph.CreationDate        AS EventDate,
        ph.CloseReasonOrNote,
        psm.WeightedScore
    FROM UserMetrics um
    JOIN Posts p ON p.OwnerUserId = um.UserId
    JOIN TagPostRankings tr ON tr.PostId = p.Id AND tr.RankInTag <= 3
    LEFT JOIN CloseReopenHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostScoreMetrics psm ON psm.PostId = p.Id
)

SELECT 
    UserId,
    Reputation,
    NetVoteScore,
    BadgeScore,
    TotalVotesCast,
    TotalBadgesEarned,
    TagName,
    PostId,
    Title,
    PostBaseScore,
    ViewCount,
    PostCreated,
    PostLastActivity,
    RankInTag,
    EventType,
    EventDate,
    CloseReasonOrNote,
    WeightedScore
FROM CombinedMetrics
ORDER BY 
    Reputation DESC,
    BadgeScore DESC,
    WeightedScore DESC,
    RankInTag ASC,
    PostCreated DESC
LIMIT 500;