WITH cte AS (
  SELECT 
    p.Id,
    p.Title,
    p.Body,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    COALESCE(
      EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, TIMESTAMP '2024-10-01 12:34:56') - p.CreationDate))/86400,
      0
    ) AS DaysSinceCreation,
    DENSE_RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS UserPostRank
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
)
SELECT 
  c.Id,
  c.Title,
  c.Body,
  c.OwnerDisplayName,
  c.Reputation,
  c.UserCreationDate,
  c.PostStatus,
  c.DaysSinceCreation,
  c.UserPostRank,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = c.Id AND v.VoteTypeId = 2
  ) AS UpVotes,
  (
    SELECT COUNT(*)
    FROM Votes v
    WHERE v.PostId = c.Id AND v.VoteTypeId = 3
  ) AS DownVotes,
  (
    SELECT COUNT(*)
    FROM Comments cm
    WHERE cm.PostId = c.Id
  ) AS CommentCount,
  CASE 
    WHEN c.DaysSinceCreation <= 7 THEN 'New'
    WHEN c.DaysSinceCreation <= 30 THEN 'Recent'
    ELSE 'Old'
  END AS AgeCategory,
  CASE
    WHEN c.Reputation < 100 THEN 'Low'
    WHEN c.Reputation < 1000 THEN 'Medium'
    ELSE 'High'
  END AS ReputationCategory,
  CASE
    WHEN c.UserPostRank <= 5 THEN 'Top 5'
    WHEN c.UserPostRank <= 10 THEN 'Top 10'
    ELSE 'Other'
  END AS UserPostRankCategory
FROM cte c
ORDER BY c.DaysSinceCreation DESC, (
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 2)
  -
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.Id AND v.VoteTypeId = 3)
) DESC;