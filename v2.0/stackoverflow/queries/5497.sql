-- {"query": "5497.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 443} 
WITH
TopTags AS (
  SELECT
    t.TagName,
    SUM(p.Score) AS TotalScore,
    AVG(p.ViewCount) AS AvgViews,
    COUNT(*) AS PostCount
  FROM Posts p
  JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
)
SELECT
  u.DisplayName AS UserName,
  u.Reputation,
  u.Location,
  u.AboutMe,
  t.TagName,
  t.TotalScore,
  t.AvgViews,
  t.PostCount,
  ra.PostId,
  ra.Title AS PostTitle,
  ra.CreationDate AS PostDate,
  ra.Score AS PostScore,
  ra.ViewCount AS PostViews,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) AS UserPostCount,
  (SELECT MAX(CreationDate) FROM Votes v WHERE v.UserId = u.Id) AS LastVoteDate,
  (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount
FROM TopTags t
JOIN RecentActivity ra ON ra.OwnerUserId = (
  SELECT Id FROM Users WHERE Id = ra.OwnerUserId
)
JOIN Users u ON u.Id = ra.OwnerUserId
LEFT JOIN PostLinks pl ON pl.PostId = ra.PostId
LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
WHERE
  t.TotalScore > 100
  AND t.PostCount > 5
  AND u.Reputation >= 1000
ORDER BY t.TotalScore DESC, t.PostCount DESC
LIMIT 50;