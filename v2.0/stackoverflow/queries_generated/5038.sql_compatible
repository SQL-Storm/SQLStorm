WITH 
RecentActiveUsers AS (
  SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
         ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
  FROM Users u
  WHERE u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days'
),
TopTags AS (
  SELECT t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId,
         ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS rn
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
QualifiedPosts AS (
  SELECT p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId,
         p.Tags, p.LastActivityDate, p.PostTypeId,
         (p.Score * 2.0
          + COALESCE(p.ViewCount,0) * 0.01
          + (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.BountyAmount IS NOT NULL) * 0.5
          + CASE WHEN p.OwnerUserId IN (SELECT Id FROM Users WHERE Reputation > 10000) THEN 5 ELSE 0 END
          ) AS DerivedScore
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2 years'
    AND p.Tags IS NOT NULL
),
CorrelatedSubquery AS (
  SELECT cp.Id,
         cp.Title,
         cp.DerivedScore,
         cp.LastActivityDate,
         cp.Tags,
         cp.OwnerUserId,
         (SELECT u.DisplayName FROM Users u WHERE u.Id = cp.OwnerUserId) AS OwnerDisplayName,
         (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cp.Id) AS CommentCount,
         (SELECT MAX(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)
            FROM Votes v2 JOIN VoteTypes vt ON vt.Id = v2.VoteTypeId
            WHERE v2.PostId = cp.Id) AS HasUpMod,
         ROW_NUMBER() OVER (ORDER BY cp.DerivedScore DESC, cp.LastActivityDate DESC) AS rn
  FROM QualifiedPosts cp
),
Aggregated AS (
  SELECT c.Id,
         c.Title,
         c.DerivedScore,
         c.OwnerDisplayName,
         c.CommentCount,
         c.HasUpMod,
         c.LastActivityDate,
         c.Tags,
         c.OwnerUserId,
         CONCAT('P-', c.Id, '-', CAST(EXTRACT(EPOCH FROM c.LastActivityDate) AS bigint)) AS CompositeKey
  FROM CorrelatedSubquery c
  WHERE c.DerivedScore > (SELECT AVG(DerivedScore) FROM CorrelatedSubquery)
)
SELECT
  a.Id AS PostId,
  a.Title,
  a.OwnerDisplayName,
  a.DerivedScore,
  a.CommentCount,
  a.LastActivityDate,
  a.Tags,
  a.CompositeKey,
  u_r.Id AS ActiveUserId,
  u_r.DisplayName AS ActiveUserName,
  u_r.Reputation AS ActiveUserReputation
FROM Aggregated a
LEFT JOIN (
  SELECT *
  FROM RecentActiveUsers
  WHERE rn <= 50
) u_r ON u_r.Id = a.OwnerUserId
GROUP BY
  a.Id,
  a.Title,
  a.OwnerDisplayName,
  a.DerivedScore,
  a.CommentCount,
  a.LastActivityDate,
  a.Tags,
  a.CompositeKey,
  u_r.Id,
  u_r.DisplayName,
  u_r.Reputation,
  a.OwnerUserId
ORDER BY a.DerivedScore DESC, a.LastActivityDate DESC
LIMIT 100;