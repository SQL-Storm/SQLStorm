WITH RecursiveBadgesCTE AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    b.Class,
    b.Name AS BadgeName,
    b.Date,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS ACnt
  FROM Users u
  LEFT JOIN Badges b ON u.Id = b.UserId
)
SELECT
  r.UserId,
  r.DisplayName,
  r.Class,
  r.BadgeName,
  r.Date,
  r.ACnt
FROM RecursiveBadgesCTE r
WHERE r.ACnt = 1;