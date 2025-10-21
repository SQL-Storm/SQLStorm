WITH RECURSIVE RecursiveTaggedPosts AS (
  SELECT
    p.Id,
    p.Title,
    COALESCE(p.Tags, '') AS Tags,
    string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagArray,
    1 AS Level,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1

  UNION ALL

  SELECT
    r.PostId AS Id,
    p.Title,
    COALESCE(p.Tags, '') AS Tags,
    string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagArray,
    Level + 1 AS Level,
    p.OwnerUserId
  FROM PostLinks r
  JOIN Posts p ON r.RelatedPostId = p.Id
  JOIN RecursiveTaggedPosts rt ON r.PostId = rt.Id
  WHERE rt.Level < 5
)

SELECT
  u.DisplayName AS UserName,
  COUNT(DISTINCT rp.Id) AS DistinctTaggedPosts,
  SUM(p.Score) AS TotalScore,
  COUNT(DISTINCT v.Id) AS DistinctVotes,
  SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
  SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
  COUNT(DISTINCT c.Id) AS DistinctComments
FROM RecursiveTaggedPosts rp
JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN Posts p ON rp.Id = p.Id
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Comments c ON p.Id = c.PostId
GROUP BY u.DisplayName
ORDER BY DistinctTaggedPosts DESC, TotalScore DESC
LIMIT 50;