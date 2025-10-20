-- {"query": "24035.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3506} 

WITH UserStats AS (
    SELECT
        u.Id                     AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                                 AS QCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                                 AS ACount,
        SUM(p.Score) FILTER (WHERE p.PostTypeId = 1)                            AS TotalScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)                       AS TotalUpOrds,
        COUNT(c.Id)                                                             AS TotalComm,
        COUNT(DISTINCT pl.Id) FILTER (WHERE pl.LinkTypeId = 3)                   AS Duplicates,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC)                          AS Rnk
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS Gold,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS Silver
    FROM Badges
    GROUP BY UserId
)
SELECT
    us.UserId,
    CONCAT('user-', LPAD(CAST(us.UserId AS TEXT), 8, '0'))                     AS Slug,
    COALESCE(us.DisplayName, '<anon>')                                        AS Name,
    us.Reputation,
    us.TotalScore,
    us.QCount             AS Questions,
    us.ACount             AS Answers,
    us.TotalUpOrds        AS Upvotes,
    bc.Gold,
    bc.Silver,
    us.Duplicates,
    us.TotalComm          AS Comments,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = us.UserId
     AND c.CreationDate >= NOW() - INTERVAL '7 days')                        AS WeeklyComments,
    CASE WHEN us.Rnk <= 5 THEN 'Elite'
         WHEN us.Rnk <= 20 THEN 'Top'
         ELSE 'Other' END                                                    AS Tier,
    STRING_AGG(DISTINCT p.Tags, ',') FILTER (WHERE p.PostTypeId = 1)          AS UsedTags,
    TO_CHAR(NOW() - INTERVAL '30 days', 'YYYY-MM-DD')                         AS BenchDate
FROM UserStats us
LEFT JOIN BadgeCounts bc  ON bc.UserId = us.UserId
LEFT JOIN Posts p          ON p.OwnerUserId = us.UserId AND p.PostTypeId = 1
WHERE us.Reputation > 3000
  AND (us.Reputation - us.TotalScore) / CAST(us.Reputation AS NUMERIC) > 0.2
  AND (us.TotalComm IS NULL OR us.TotalComm > 3)
GROUP BY us.UserId, us.DisplayName, us.Reputation, us.TotalScore,
         us.QCount, us.ACount, us.TotalUpOrds, bc.Gold, bc.Silver,
         us.Duplicates, us.TotalComm, us.Rnk
ORDER BY us.TotalScore DESC
LIMIT 50

UNION ALL

SELECT
    0,
    'summary',
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM (SELECT 1) d;
