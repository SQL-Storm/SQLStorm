-- {"query": "3068.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1947} 

WITH 
-- Aggregate posts per user, including question/answer split and recent activity
UserPostAgg AS (
    SELECT 
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(p.Id)                          AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.Score IS NOT NULL)   AS AvgPostScore,
        MAX(p.CreationDate)                 AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

-- Aggregate badges per user, list distinct names concatenated
UserBadgeAgg AS (
    SELECT 
        b.UserId,
        COUNT(*)                                 AS BadgeCount,
        MAX(b.Date)                              AS LastBadgeDate,
        STRING_AGG(DISTINCT b.Name, ', ') 
            FILTER (WHERE b.Name IS NOT NULL)   AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),

-- Latest vote per post plus up/down counts (used later via join)
PostVoteAgg AS (
    SELECT 
        v.PostId,
        MAX(v.CreationDate)                      AS LastVoteDate,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount
    FROM Votes v
    GROUP BY v.PostId
),

-- First close / reopen timestamps per post from PostHistory
PostHistoryClose AS (
    SELECT 
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS CloseDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS ReopenDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),

-- Collapse close/reopen info to the owning user
UserCloseInfo AS (
    SELECT 
        p.OwnerUserId                                   AS UserId,
        MAX(ch.CloseDate)                               AS LastCloseDate,
        MAX(ch.ReopenDate)                              AS LastReopenDate
    FROM Posts p
    LEFT JOIN PostHistoryClose ch ON ch.PostId = p.Id
    GROUP BY p.OwnerUserId
)

-- Final result set
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.TotalPosts,
    upa.QuestionCount,
    upa.AnswerCount,
    upa.AvgPostScore,
    COALESCE(uba.BadgeCount, 0)               AS BadgeCount,
    uba.BadgeNames,
    upa.LastPostDate,
    uba.LastBadgeDate,
    ROW_NUMBER() OVER (ORDER BY upa.TotalPosts DESC NULLS LAST)   AS PostRank,
    PERCENT_RANK() OVER (ORDER BY upa.AvgPostScore DESC)        AS ScorePercentile,
    CASE 
        WHEN upa.TotalPosts = 0                     THEN 'NoPosts'
        WHEN upa.QuestionCount > upa.AnswerCount    THEN 'QuestionHeavy'
        ELSE 'AnswerHeavy'
    END                                         AS ActivityProfile,
    COALESCE(uci.LastCloseDate, '2099-01-01'::timestamp) AS LastCloseDate,
    uci.LastReopenDate
FROM UserPostAgg upa
LEFT JOIN UserBadgeAgg uba   ON uba.UserId = upa.UserId
LEFT JOIN UserCloseInfo uci  ON uci.UserId = upa.UserId
WHERE upa.TotalPosts > 0 OR uba.BadgeCount IS NOT NULL

UNION ALL

-- Users with absolutely no posts (to stress outer joins and NOT EXISTS)
SELECT
    u.Id,
    u.DisplayName,
    0                                    AS TotalPosts,
    0                                    AS QuestionCount,
    0                                    AS AnswerCount,
    NULL                                 AS AvgPostScore,
    0                                    AS BadgeCount,
    NULL                                 AS BadgeNames,
    NULL                                 AS LastPostDate,
    NULL                                 AS LastBadgeDate,
    ROW_NUMBER() OVER (ORDER BY u.Id)   AS PostRank,
    NULL                                 AS ScorePercentile,
    'NoPosts'                            AS ActivityProfile,
    NULL                                 AS LastCloseDate,
    NULL                                 AS LastReopenDate
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)

ORDER BY PostRank
LIMIT 100;
