-- {"query": "5154.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 863} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    p.ParentId,
    p.AcceptedAnswerId
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '180 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore
  FROM Posts p
  JOIN UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS t(TagName)
    ON TRUE
  GROUP BY t.TagName
),
UserEngagement AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT r.PostId) AS RepliedPosts,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast,
    MAX(p.LastActivityDate) AS LastActivePost
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT Id AS PostId
    FROM Comments
  ) c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS PostDate
    FROM Votes
    GROUP BY PostId
  ) r ON r.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
)
SELECT
  r.Id AS PostId,
  r.PostTypeId,
  pt.Name AS PostTypeName,
  r.Title,
  r.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  r.CreationDate,
  r.LastActivityDate,
  r.Score,
  r.ViewCount,
  r.Tags,
  r.CommentCount,
  r.FavoriteCount,
  CASE
    WHEN r.AcceptedAnswerId IS NULL THEN NULL
    ELSE r.AcceptedAnswerId
  END AS AcceptedAnswerId,
  CASE
    WHEN r.ParentId IS NULL THEN NULL
    ELSE r.ParentId
  END AS ParentId,
  COALESCE(b.Name, 'Unknown') AS BadgeName,
  CAST(
    ROW_NUMBER() OVER (PARTITION BY r.PostTypeId ORDER BY r.Score DESC, r.ViewCount DESC) AS int
  ) AS RankWithinType,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.Id) AS RelatedLinkCount,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.Id) AS CommentCountTotal,
  (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = r.Id AND v2.VoteTypeId = 2) AS UpvotesForPost,
  (SELECT JSON_ARRAYAGG(v2.UserId) FROM Votes v2 WHERE v2.PostId = r.Id AND v2.VoteTypeId = 6) AS CloseVotersJson,
  (SELECT AVG(v3.BountyAmount) FROM Votes v3 WHERE v3.PostId = r.Id AND v3.BountyAmount > 0) AS AvgBounty
FROM
  RecentActivePosts r
  LEFT JOIN PostTypes pt ON r.PostTypeId = pt.Id
  LEFT JOIN Users u ON r.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date = (SELECT MAX(Date) FROM Badges b2 WHERE b2.UserId = u.Id)
  LEFT JOIN TopTags tt ON r.Tags LIKE '%' || tt.TagName || '%'
  LEFT JOIN (
    SELECT DISTINCT UserId, PostId
    FROM Votes
  ) v ON v.PostId = r.Id
ORDER BY
  r.LastActivityDate DESC
LIMIT 100;