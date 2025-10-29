-- {"query": "3865.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1595} 
WITH UserStats AS (
    SELECT
        u.Id                                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(q.TotalQuestionScore, 0)        AS TotalQuestionScore,
        COALESCE(a.TotalAnswerScore,   0)        AS TotalAnswerScore,
        COALESCE(b.BadgeCount,        0)        AS BadgeCount
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, SUM(Score) AS TotalQuestionScore
        FROM Posts
        WHERE PostTypeId = 1            -- questions
        GROUP BY OwnerUserId
    ) q ON u.Id = q.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId, SUM(Score) AS TotalAnswerScore
        FROM Posts
        WHERE PostTypeId = 2            -- answers
        GROUP BY OwnerUserId
    ) a ON u.Id = a.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
),

UserTopTags AS (
    SELECT
        u.Id                                            AS UserId,
        STRING_AGG(t.TagName, ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTags
    FROM Users u
    LEFT JOIN Posts p
           ON p.OwnerUserId = u.Id
          AND p.PostTypeId = 1           -- only questions have tags
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) pt ON TRUE
    LEFT JOIN Tags t
           ON t.TagName = pt.tag
    GROUP BY u.Id
),

UserRanking AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.TotalQuestionScore,
        us.TotalAnswerScore,
        us.BadgeCount,
        ut.TopTags,
        RANK()     OVER (ORDER BY us.Reputation DESC,
                                   (us.TotalQuestionScore + us.TotalAnswerScore) DESC) AS RepRank,
        ROW_NUMBER() OVER (PARTITION BY us.Reputation >= 10000
                           ORDER BY us.TotalQuestionScore DESC)                     AS HighRepRowNum
    FROM UserStats us
    LEFT JOIN UserTopTags ut ON us.UserId = ut.UserId
)

SELECT
    ur.UserId,
    ur.DisplayName,
    ur.Reputation,
    ur.TotalQuestionScore,
    ur.TotalAnswerScore,
    ur.BadgeCount,
    ur.TopTags,
    ur.RepRank,
    CASE WHEN ur.RepRank <= 10 THEN 'Top 10' END                                   AS Top10Flag,
    CASE WHEN ur.HighRepRowNum IS NOT NULL AND ur.HighRepRowNum <= 5
         THEN 'HighRepTop5' END                                                   AS HighRepTop5
FROM UserRanking ur
WHERE (ur.Reputation IS NOT NULL AND ur.Reputation > 0)
   OR (ur.TotalQuestionScore + ur.TotalAnswerScore) > 0

UNION ALL

SELECT
    -1                                    AS UserId,
    'Anonymous'                           AS DisplayName,
    NULL                                  AS Reputation,
    0                                     AS TotalQuestionScore,
    0                                     AS TotalAnswerScore,
    0                                     AS BadgeCount,
    NULL                                  AS TopTags,
    NULL                                  AS RepRank,
    NULL                                  AS Top10Flag,
    NULL                                  AS HighRepTop5
WHERE NOT EXISTS (SELECT 1 FROM Users WHERE Reputation > 0);