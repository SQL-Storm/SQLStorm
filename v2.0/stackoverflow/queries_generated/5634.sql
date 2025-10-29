-- {"query": "5634.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 996} 
WITH
RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS PostCount,
    AVG(p.Score) AS AvgScore,
    SUM(p.ViewCount) AS TotalViews
  FROM Posts p
  JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) AS tgs ON true
  JOIN Tags t ON t.TagName = tgs.TagName
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS PostsCreated,
    MAX(p.LastActivityDate) AS LastActive,
    SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id, u.DisplayName
),
CrossLink AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    lt.Name AS LinkType,
    pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.RelatedPostId <> pl.PostId
),
Commentary AS (
  SELECT
    c.PostId,
    AVG(CASE WHEN c.Score IS NULL THEN 0 ELSE c.Score END) AS AvgCommentScore,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
Finally AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.LastActivityDate,
    ro.Name AS OwnerBadge,
    ur.DisplayName AS OwnerDisplayName,
    vtd.Name AS VoteTypeName,
    v.BountyAmount,
    cmt.CommentCount,
    cs.AvgCommentScore,
    ls.NumLinks
  FROM Posts p
  LEFT JOIN Users ur ON ur.Id = p.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
  LEFT JOIN PostHistory ph ON ph.PostId = p.Id
  LEFT JOIN PostHistoryTypes vtd ON vtd.Id = ph.PostHistoryTypeId
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS NumLinks
    FROM PostLinks
    GROUP BY PostId
  ) ls ON ls.PostId = p.Id
  LEFT JOIN Commentary cmt ON cmt.PostId = p.Id
  LEFT JOIN (
    SELECT u.Id, b.Name AS OwnerBadge
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
  ) ro ON ro.OwnerBadge IS NOT NULL AND ro.Id = p.OwnerUserId
  LEFT JOIN TagStats ts ON ts.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > NOW() - INTERVAL '180 days'
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  ViewCount,
  Score,
  OwnerUserId,
  LastActivityDate,
  OwnerDisplayName,
  COALESCE(OwnerBadge, 'NoBadge') AS OwnerBadge,
  VoteTypeName,
  COALESCE(BountyAmount, 0) AS BountyAmount,
  CommentCount,
  COALESCE(AvgCommentScore, 0) AS AvgCommentScore,
  COALESCE(NumLinks, 0) AS NumLinks,
  (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS GlobalAvgQuestionScore,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = Finally.OwnerUserId) AS PostsByOwner
FROM Finally
ORDER BY LastActivityDate DESC, ViewCount DESC
LIMIT 200;