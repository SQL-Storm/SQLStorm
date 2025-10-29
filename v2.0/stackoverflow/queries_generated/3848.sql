-- {"query": "3848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2688} 

/*  Comprehensive benchmark query using CTEs, window functions, outer joins, 
    correlated subqueries, set operators, string manipulation and NULL logic   */
WITH 
-- Aggregate post statistics per user
UserPostStats AS (
    SELECT 
        u.Id                               AS UserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)                     AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)                     AS AnswerCount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)                   AS QuestionScoreSum,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 2)                   AS AnswerScoreSum,
        MAX(p.CreationDate)                                          AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),

-- Badge aggregates per user
UserBadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date)                         AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),

-- Explode tags for each user's questions and count usage
UserTagCounts AS (
    SELECT 
        u.Id                                   AS UserId,
        tag,
        COUNT(*) OVER (PARTITION BY tag)       AS cnt
    FROM Users u
    LEFT JOIN LATERAL (
        SELECT 
            UNNEST(STRING_TO_ARRAY(
                SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'
            )) AS tag
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1               -- only questions
    ) AS t ON TRUE
    WHERE tag IS NOT NULL
),

-- Pick the most frequent tag per user
TopUserTag AS (
    SELECT 
        utc.UserId,
        utc.tag,
        utc.cnt,
        ROW_NUMBER() OVER (PARTITION BY utc.UserId 
                           ORDER BY utc.cnt DESC NULLS LAST, utc.tag) AS rn
    FROM UserTagCounts utc
),

-- Recent activity counts (correlated subqueries)
RecentUserActivity AS (
    SELECT 
        u.Id                                            AS UserId,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 2               -- up‑votes
           AND v.CreationDate > (NOW() - INTERVAL '7 days')
        )                                                AS RecentUpVotesGiven,
        (SELECT COUNT(*) 
         FROM Comments c 
         WHERE c.UserId = u.Id 
           AND c.CreationDate > (NOW() - INTERVAL '7 days')
        )                                                AS RecentCommentsMade
    FROM Users u
)

SELECT
    u.Id,
    COALESCE(u.DisplayName, 'Anonymous')                AS DisplayName,
    u.Reputation,
    COALESCE(ps.QuestionCount, 0)                       AS QuestionCount,
    COALESCE(ps.AnswerCount, 0)                         AS AnswerCount,
    COALESCE(ps.QuestionScoreSum,0) / NULLIF(COALESCE(ps.QuestionCount,0),0) AS AvgQuestionScore,
    COALESCE(ps.AnswerScoreSum,0)   / NULLIF(COALESCE(ps.AnswerCount,0),0)   AS AvgAnswerScore,
    COALESCE(bs.GoldBadges,   0)                        AS GoldBadges,
    COALESCE(bs.SilverBadges, 0)                        AS SilverBadges,
    COALESCE(bs.BronzeBadges, 0)                        AS BronzeBadges,
    CASE
        WHEN u.CreationDate > (NOW() - INTERVAL '1 year') THEN 'Newbie'
        WHEN u.Reputation >= 100000                        THEN 'Legend'
        WHEN u.Reputation >= 20000                         THEN 'Expert'
        ELSE                                                'Member'
    END                                                AS UserTier,
    t.tag                                              AS TopTag,
    t.cnt                                              AS TopTagUsage,
    CASE
        WHEN ps.LastPostDate IS NULL                      THEN NULL
        WHEN ps.LastPostDate > (NOW() - INTERVAL '30 days') THEN 'Active'
        ELSE                                                'Dormant'
    END                                                AS RecentActivity,
    rua.RecentUpVotesGiven,
    rua.RecentCommentsMade
FROM Users u
LEFT JOIN UserPostStats   ps  ON ps.UserId = u.Id
LEFT JOIN UserBadgeStats  bs  ON bs.UserId = u.Id
LEFT JOIN TopUserTag      t   ON t.UserId = u.Id AND t.rn = 1
LEFT JOIN RecentUserActivity rua ON rua.UserId = u.Id
WHERE u.Id NOT IN (
      SELECT DISTINCT UserId 
      FROM Badges 
      WHERE Class = 1 AND Name ILIKE '%moderator%'
)
ORDER BY u.Reputation DESC
LIMIT 100

UNION ALL

/*  Totals row – aggregates across the whole data set  */
SELECT
    NULL                                              AS Id,
    'TOTAL'                                           AS DisplayName,
    SUM(u.Reputation)                                 AS Reputation,
    SUM(COALESCE(ps.QuestionCount,0))                 AS QuestionCount,
    SUM(COALESCE(ps.AnswerCount,0))                   AS AnswerCount,
    SUM(COALESCE(ps.QuestionScoreSum,0)) / NULLIF(SUM(COALESCE(ps.QuestionCount,0)),0) AS AvgQuestionScore,
    SUM(COALESCE(ps.AnswerScoreSum,0))   / NULLIF(SUM(COALESCE(ps.AnswerCount,0)),0)   AS AvgAnswerScore,
    SUM(COALESCE(bs.GoldBadges,0))   AS GoldBadges,
    SUM(COALESCE(bs.SilverBadges,0)) AS SilverBadges,
    SUM(COALESCE(bs.BronzeBadges,0)) AS BronzeBadges,
    NULL AS UserTier,
    NULL AS TopTag,
    NULL AS TopTagUsage,
    NULL AS RecentActivity,
    NULL AS RecentUpVotesGiven,
    NULL AS RecentCommentsMade
FROM Users u
LEFT JOIN UserPostStats  ps ON ps.UserId = u.Id
LEFT JOIN UserBadgeStats bs ON bs.UserId = u.Id
HAVING COUNT(u.Id) > 0;
