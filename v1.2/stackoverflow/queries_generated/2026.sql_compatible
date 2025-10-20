WITH DirectBadgers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount,
    COALESCE(MAX(p.Score), 0) AS MaxPostScore
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
)
SELECT *
FROM DirectBadgers;