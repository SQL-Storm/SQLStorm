-- {"query": "5209.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1265} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate
  FROM Posts p
  WHERE p.LastActivityDate > NOW() - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgScorePerTag,
    MAX(p.ViewCount) AS MaxViewsForTag
  FROM RecentActivePosts rap
  JOIN LATERAL unnest(string_to_array(rap.Tags, '>')) AS tagname
      ON true
  JOIN Tags t ON t.TagName = tagname.tagname
  JOIN Posts p ON p.Id = rap.Id
  GROUP BY t.TagName
),
InfluenceMetrics AS (
  SELECT
    p.Id,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(u.Reputation, 0) AS AuthorReputation,
    u.DisplayName AS AuthorName,
    COALESCE(vt.Name, 'Unknown') AS LastVoteType,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id) AS TotalVotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.LastActivityDate > NOW() - INTERVAL '45 days'
),
ComplexDerived AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    -- computed expressions
    (CASE WHEN p.Score > 0 THEN 'Positive' WHEN p.Score < 0 THEN 'Negative' ELSE 'Neutral' END) AS ScoreMood,
    (CASE
       WHEN p.ViewCount > 1000 THEN 'Popular'
       WHEN p.ViewCount > 100 AND p.ViewCount <= 1000 THEN 'Spotted'
       ELSE 'New'
     END) AS VisibilityTier,
    (EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 3600) AS HoursSinceCreation
  FROM Posts p
),
JoinedStats AS (
  SELECT
    c.*,
    COALESCE(id.TotalVotes, 0) AS TotalVotes,
    COALESCE(ic.CommentCount, 0) AS CommentCount
  FROM ComplexDerived c
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS TotalVotes
    FROM Votes
    GROUP BY PostId
  ) id ON id.PostId = c.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS CommentCount
    FROM Comments
    GROUP BY PostId
  ) ic ON ic.PostId = c.Id
)
SELECT
  p.Id AS PostId,
  p.Title,
  p.PostTypeId,
  pt.Name AS PostTypeName,
  p.OwnerUserId,
  u.DisplayName AS OwnerDisplayName,
  u.Reputation AS OwnerReputation,
  p.CreationDate,
  p.LastActivityDate,
  p.Score,
  p.ViewCount,
  CASE
    WHEN p.AcceptedAnswerId IS NOT NULL THEN 'HasAccepted'
    ELSE 'NoAccepted'
  END AS HasAcceptedAnswer,
  p.Tags,
  COALESCE(b.Name, 'None') AS BadgeEarned,
  b.Date AS BadgeDate,
  b.Class AS BadgeClass,
  vm.TotalVotes,
  vm.CommentCount AS TotalComments,
  vm.LastVoteType,
  tgs.TagName,
  tgs.TagPostCount,
  tgs.AvgScorePerTag,
  tgs.MaxViewsForTag,
  rf.HoursSinceCreation,
  rf.ScoreMood,
  rf.VisibilityTier
FROM Posts p
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
  SELECT DISTINCT TOP 1 b.*
  FROM Badges b
  WHERE b.UserId = p.OwnerUserId
  ORDER BY b.Date DESC
) b ON b.UserId = p.OwnerUserId
LEFT JOIN Votes vm ON vm.PostId = p.Id
LEFT JOIN (
  SELECT unn.PostId, unn.TagName
  FROM (
    SELECT p.Id AS PostId, unnest(string_to_array(p.Tags, '>')) AS TagName
    FROM Posts p
  ) AS unn
) tgs ON tgs.PostId = p.Id
LEFT JOIN (
  SELECT TagName, COUNT(*) AS TagPostCount, AVG(Score) AS AvgScorePerTag, MAX(ViewCount) AS MaxViewsForTag
  FROM (
    SELECT p.Id, unnest(string_to_array(p.Tags, '>')) AS TagName, p.Score, p.ViewCount
    FROM Posts p
  ) sub
  GROUP BY TagName
) AS tgs ON tgs.TagName = unnest(string_to_array(p.Tags, '>'))
LEFT JOIN (
  SELECT PostId, SUM(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS PositiveVotes
  FROM Votes
  GROUP BY PostId
) AS rf ON rf.PostId = p.Id
ORDER BY p.LastActivityDate DESC
LIMIT 100;