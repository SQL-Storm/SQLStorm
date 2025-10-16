WITH 
RecentActivity AS (
    SELECT 
        p.Id,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId 
            ORDER BY p.Score DESC, p.ViewCount DESC
        ) AS UserRank,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c 
        ON c.PostId = p.Id 
       AND c.Score >= 0
    WHERE p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY)
),
UserBadges AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Golds,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silvers,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronzes
    FROM Badges b
    WHERE b.TagBased = TRUE
    GROUP BY b.UserId
),
TagSummaries AS (
    SELECT 
        t.TagName, 
        t.ExcerptPostId, 
        t.WikiPostId,
        t.IsRequired,
        t.Count
    FROM Tags t
    WHERE t.IsRequired = FALSE
      AND t.Count > 100
)
SELECT
    ts.TagName,
    ra.UserRank,
    ra.CommentCount,
    u.Reputation,
    COALESCE(ub.Golds, 0) * 3
  + COALESCE(ub.Silvers, 0) * 2
  + COALESCE(ub.Bronzes, 0) AS BadgeScore,
    SUBSTRING(COALESCE(p.Title, '') || ' - ' || SUBSTRING(COALESCE(p.Body, ''), 1, 50) FROM 1 FOR 100) AS PreviewText,
    (
      SELECT COUNT(*) 
      FROM PostLinks pl 
      WHERE pl.PostId = ra.Id 
        AND pl.LinkTypeId = 1
    ) AS LinkOutCount
FROM RecentActivity ra
FULL OUTER JOIN Posts p 
    ON p.Id = ra.Id
INNER JOIN TagSummaries ts 
    ON ts.ExcerptPostId = p.Id 
    OR ts.WikiPostId    = p.Id
LEFT JOIN Users u 
    ON u.Id = ra.OwnerUserId
LEFT JOIN UserBadges ub 
    ON ub.UserId = u.Id
WHERE 
    (
      ra.Score > (
        SELECT AVG(p2.Score) 
        FROM Posts p2 
        WHERE p2.OwnerUserId = ra.OwnerUserId
      )
    )
    OR ra.ViewCount > 10000
GROUP BY
    ts.TagName,
    ra.UserRank,
    ra.CommentCount,
    u.Reputation,
    ub.Golds,
    ub.Silvers,
    ub.Bronzes,
    p.Title,
    p.Body,
    ra.Id,
    ts.IsRequired,
    ts.Count
HAVING COUNT(ra.Id) > 5

INTERSECT

SELECT
    ts2.TagName,
   -1         AS UserRank,
    0         AS CommentCount,
    0         AS Reputation,
    0         AS BadgeScore,
    ''        AS PreviewText,
    0         AS LinkOutCount
FROM TagSummaries ts2

UNION

SELECT
    ts3.TagName,
    ra3.UserRank,
    ra3.CommentCount,
    u3.Reputation,
    COALESCE(ub3.Golds, 0) * 3 
  + COALESCE(ub3.Silvers, 0) * 2
  + COALESCE(ub3.Bronzes, 0) AS BadgeScore,
    SUBSTRING(COALESCE(p3.Title, '') FROM 1 FOR 20) AS PreviewText,
    (
      SELECT COUNT(*) 
      FROM Comments c3 
      WHERE c3.PostId = ra3.Id 
        AND c3.Score < 0
    ) AS LinkOutCount
FROM RecentActivity ra3
JOIN Posts p3 
    ON p3.Id = ra3.Id
JOIN TagSummaries ts3 
    ON ts3.ExcerptPostId = p3.Id
LEFT JOIN Users u3 
    ON u3.Id = ra3.OwnerUserId
LEFT JOIN UserBadges ub3 
    ON ub3.UserId = u3.Id
WHERE ra3.ViewCount BETWEEN 1000 AND 5000;