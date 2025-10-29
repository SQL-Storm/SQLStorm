-- {"query": "3889.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2611} 

/*  Complex benchmarking query leveraging many SQL constructs  */
WITH RecentAnswers AS (
    SELECT
        a.Id,
        a.OwnerUserId,
        a.ParentId,
        a.Score,
        a.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.CreationDate DESC) AS rn
    FROM Posts a
    WHERE a.PostTypeId = 2                                 -- answers only
      AND a.CreationDate >= DATEADD(year, -1, CURRENT_TIMESTAMP)
),
UserBadgeAgg AS (
    SELECT
        b.UserId,
        COUNT(*)                               AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(b.Date)                            AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(c.Id)                           AS CommentCount,
        MAX(c.CreationDate)                   AS LastCommentDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.OwnerUserId
),
UserTagStats AS (
    SELECT
        u.Id                                    AS UserId,
        STRING_AGG(DISTINCT REPLACE(REPLACE(t.TagName, '>', ''), '<', ''), ',') AS TagsUsed,
        COUNT(DISTINCT t.Id)                    AS DistinctTagCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 2
    CROSS APPLY (
        SELECT UNNEST(string_to_array(p.Tags, '><')) AS tag_raw
    ) AS ts
    JOIN Tags t ON t.TagName = REPLACE(REPLACE(ts.tag_raw, '>', ''), '<', '')
    GROUP BY u.Id
),
AnswerCounts AS (
    SELECT OwnerUserId, COUNT(*) AS TotalAnswers
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
),
AcceptedAnswerCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS AcceptedAnswers
    FROM Posts p
    JOIN Posts q ON q.Id = p.ParentId AND q.PostTypeId = 1
    WHERE p.PostTypeId = 2
      AND q.AcceptedAnswerId = p.Id
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id                                   AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.LastBadgeDate,
    uc.CommentCount,
    uc.LastCommentDate,
    ut.TagsUsed,
    ut.DistinctTagCount,
    ra.Score                               AS LatestAnswerScore,
    ra.CreationDate                        AS LatestAnswerDate,
    COALESCE(ac.TotalAnswers,0)            AS TotalAnswers,
    COALESCE(aa.AcceptedAnswers,0)         AS AcceptedAnswers,
    CASE
        WHEN COALESCE(ac.TotalAnswers,0) = 0 THEN NULL
        ELSE ROUND(100.0 * aa.AcceptedAnswers / ac.TotalAnswers, 2)
    END                                    AS AcceptanceRate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
FROM Users u
LEFT JOIN UserBadgeAgg ub            ON ub.UserId = u.Id
LEFT JOIN UserCommentStats uc        ON uc.OwnerUserId = u.Id
LEFT JOIN UserTagStats ut            ON ut.UserId = u.Id
LEFT JOIN RecentAnswers ra           ON ra.OwnerUserId = u.Id AND ra.rn = 1
LEFT JOIN AnswerCounts ac            ON ac.OwnerUserId = u.Id
LEFT JOIN AcceptedAnswerCounts aa    ON aa.OwnerUserId = u.Id
WHERE (u.Reputation > 20000 OR ub.GoldBadges > 0)
  AND (ra.Score IS NOT NULL OR ac.TotalAnswers > 5)
  AND COALESCE(ut.DistinctTagCount,0) >= 3

UNION ALL

SELECT
    -1                                   AS UserId,
    'AggregatedTotals'                   AS DisplayName,
    SUM(u.Reputation)                    AS Reputation,
    SUM(ub.TotalBadges)                  AS TotalBadges,
    SUM(ub.GoldBadges)                   AS GoldBadges,
    MAX(ub.LastBadgeDate)               AS LastBadgeDate,
    SUM(uc.CommentCount)                AS CommentCount,
    MAX(uc.LastCommentDate)             AS LastCommentDate,
    NULL                                 AS TagsUsed,
    NULL                                 AS DistinctTagCount,
    NULL                                 AS LatestAnswerScore,
    NULL                                 AS LatestAnswerDate,
    SUM(ac.TotalAnswers)                AS TotalAnswers,
    SUM(aa.AcceptedAnswers)             AS AcceptedAnswers,
    NULL                                 AS AcceptanceRate,
    NULL                                 AS ReputationRank
FROM Users u
LEFT JOIN UserBadgeAgg ub            ON ub.UserId = u.Id
LEFT JOIN UserCommentStats uc        ON uc.OwnerUserId = u.Id
LEFT JOIN UserTagStats ut            ON ut.UserId = u.Id
LEFT JOIN AnswerCounts ac            ON ac.OwnerUserId = u.Id
LEFT JOIN AcceptedAnswerCounts aa    ON aa.OwnerUserId = u.Id
WHERE u.Id IS NOT NULL

ORDER BY ReputationRank NULLS LAST, Reputation DESC
LIMIT 100;
