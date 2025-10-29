-- {"query": "3968.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1619} 

WITH 
/* aggregate basic activity counters per user */
UserActivity AS (
    SELECT 
        u.Id,
        COALESCE(u.DisplayName, '[deleted]') AS DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id)                     AS PostCount,
        (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS AnswerCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id)                      AS CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id)                         AS VoteGivenCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id)                        AS BadgeCount,
        (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id)        AS LastPostDate
    FROM Users u
),
/* average post score per user (may be NULL) */
AvgScore AS (
    SELECT OwnerUserId, AVG(Score)::numeric(10,2) AS AvgScore
    FROM Posts
    GROUP BY OwnerUserId
),
/* combine activity with score, apply window functions */
RankedUsers AS (
    SELECT 
        a.Id,
        a.DisplayName,
        a.Reputation,
        a.PostCount,
        a.AnswerCount,
        a.CommentCount,
        a.VoteGivenCount,
        a.BadgeCount,
        a.LastPostDate,
        s.AvgScore,
        ROW_NUMBER() OVER (ORDER BY a.Reputation DESC, a.PostCount DESC) AS RepRank,
        RANK() OVER (
            PARTITION BY 
                CASE 
                    WHEN a.Reputation >= 10000 THEN 'high' 
                    WHEN a.Reputation >= 1000  THEN 'mid' 
                    ELSE 'low' 
                END 
            ORDER BY a.BadgeCount DESC
        ) AS BadgeRank
    FROM UserActivity a
    LEFT JOIN AvgScore s ON s.OwnerUserId = a.Id
),
/* final selection of the top 100 active users */
TopActiveUsers AS (
    SELECT 
        Id,
        DisplayName || ' (ID:' || Id || ')'                                   AS UserLabel,
        Reputation,
        PostCount,
        AnswerCount,
        CommentCount,
        VoteGivenCount,
        BadgeCount,
        AvgScore,
        RepRank,
        BadgeRank,
        CASE 
            WHEN LastPostDate IS NULL                     THEN 'Never posted'
            WHEN LastPostDate < CURRENT_DATE - INTERVAL '1 year' THEN 'Stale'
            ELSE 'Active'
        END                                                                      AS ActivityStatus
    FROM RankedUsers
    WHERE RepRank <= 100
)
SELECT *
FROM TopActiveUsers
WHERE ActivityStatus = 'Active'

UNION ALL

/* users with no detectable activity */
SELECT
    u.Id,
    COALESCE(u.DisplayName, '[deleted]') || ' (ID:' || u.Id || ')' AS UserLabel,
    COALESCE(u.Reputation,0)               AS Reputation,
    0                                      AS PostCount,
    0                                      AS AnswerCount,
    0                                      AS CommentCount,
    0                                      AS VoteGivenCount,
    0                                      AS BadgeCount,
    NULL                                   AS AvgScore,
    NULL                                   AS RepRank,
    NULL                                   AS BadgeRank,
    'No activity'                          AS ActivityStatus
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p      WHERE p.OwnerUserId = u.Id)
  AND NOT EXISTS (SELECT 1 FROM Comments c   WHERE c.UserId      = u.Id)
  AND NOT EXISTS (SELECT 1 FROM Badges b    WHERE b.UserId      = u.Id)
ORDER BY Reputation DESC NULLS LAST, PostCount DESC;
