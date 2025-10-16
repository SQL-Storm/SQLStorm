WITH
RecentQuestions AS (
    SELECT
        q.Id                 AS QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.ViewCount,
        q.Title,
        COUNT(a.Id) OVER (
            PARTITION BY q.OwnerUserId
            ORDER BY q.CreationDate
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                    AS CumulativeAnswersSeen,
        ROW_NUMBER() OVER (
            PARTITION BY q.OwnerUserId
            ORDER BY q.CreationDate DESC
        )                    AS RN
    FROM Posts q
    LEFT JOIN Posts a
        ON a.ParentId = q.Id
       AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= CAST('2024-10-01' AS DATE) - INTERVAL '30' DAY
),
UserActivity AS (
    SELECT
        u.Id                  AS UserId,
        u.DisplayName,
        COUNT(rq.QuestionId)  AS RecentQCount,
        SUM(COALESCE(rq.ViewCount,0)) AS TotalRecentViews,
        MAX(rq.CreationDate)  AS LastQDate
    FROM Users u
    LEFT JOIN RecentQuestions rq
        ON rq.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
BadgeStats AS (
    SELECT
        u.Id AS UserId,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS Golds,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS Silvers,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS Bronzes
    FROM Users u
),
Combined AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.RecentQCount,
        ua.TotalRecentViews,
        bs.Golds,
        bs.Silvers,
        bs.Bronzes,
        ua.LastQDate
    FROM UserActivity ua
    LEFT JOIN BadgeStats bs
        ON bs.UserId = ua.UserId
),
Ranked AS (
    SELECT
        c.UserId,
        c.DisplayName,
        c.RecentQCount,
        c.TotalRecentViews,
        c.Golds,
        c.Silvers,
        c.Bronzes,
        c.LastQDate,
        ROW_NUMBER() OVER (
            ORDER BY c.Golds DESC, c.TotalRecentViews DESC
        ) AS GlobalRank,
        CASE
            WHEN c.TotalRecentViews >= 10000 THEN 'A'
            WHEN c.TotalRecentViews >= 1000  THEN 'B'
            ELSE 'C'
        END AS ViewTier,
        CONCAT(
            COALESCE(c.DisplayName,'<anonymous>'),
            ' (Q', COALESCE(CAST(c.RecentQCount AS VARCHAR), '0'), ', B',
            COALESCE(CAST(c.Golds AS VARCHAR),'0'), '/', COALESCE(CAST(c.Silvers AS VARCHAR),'0'), '/', COALESCE(CAST(c.Bronzes AS VARCHAR),'0'), ')'
        ) AS Label
    FROM Combined c
    WHERE (COALESCE(c.Golds,0) + COALESCE(c.Silvers,0) + COALESCE(c.Bronzes,0)) > 0
      AND COALESCE(c.RecentQCount,0)    >  1
)
SELECT *
FROM Ranked

UNION

SELECT
    u.Id            AS UserId,
    u.DisplayName,
    0               AS RecentQCount,
    0               AS TotalRecentViews,
    0               AS Golds,
    0               AS Silvers,
    0               AS Bronzes,
    u.CreationDate  AS LastQDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS GlobalRank,
    'Z'             AS ViewTier,
    CONCAT(u.DisplayName,' <no questions>')       AS Label
FROM Users u
WHERE NOT EXISTS (
    SELECT 1 FROM Posts p
    WHERE p.OwnerUserId = u.Id
      AND p.PostTypeId   = 1
)

EXCEPT

SELECT
    r.UserId,
    r.DisplayName,
    r.RecentQCount,
    r.TotalRecentViews,
    r.Golds,
    r.Silvers,
    r.Bronzes,
    r.LastQDate,
    r.GlobalRank,
    r.ViewTier,
    r.Label
FROM Ranked r
WHERE r.TotalRecentViews < 100

ORDER BY GlobalRank;