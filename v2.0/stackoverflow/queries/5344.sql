-- {"query": "5344.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1016}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.ContentLicense,
    p.ParentId,
    p.AcceptedAnswerId,
    p.ClosedDate,
    p.CommunityOwnedDate,
    AVG(p.Score) OVER (PARTITION BY CAST(p.CreationDate AS date) ORDER BY p.CreationDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS AvgScoreLast7
  FROM Posts p
),
TagSplit AS (
  SELECT
    rp.PostId,
    rp.PostTypeId,
    rp.Title,
    rp.Tags,
    unnest(string_to_array(substr(rp.Tags, 2, length(rp.Tags)-2), '><')) AS Tag
  FROM RankedPosts rp
  WHERE rp.PostTypeId = 1
),
OpenVsClosed AS (
  SELECT
    rp.PostId,
    rp.Title,
    CASE
      WHEN rp.ClosedDate IS NULL THEN 'Open'
      ELSE 'Closed'
    END AS Status
  FROM RankedPosts rp
),
JoinedInfo AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    rp.Score,
    rp.ViewCount,
    rp.CommentCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.LastEditDate,
    rp.LastEditorDisplayName,
    rp.LastEditorUserId,
    rp.Body,
    rp.Tags,
    rp.ContentLicense,
    CASE
      WHEN rp.OwnerUserId IS NULL THEN 'Guest'
      ELSE 'User'
    END AS OwnerType
  FROM RankedPosts rp
  LEFT JOIN Users u ON rp.OwnerUserId = u.Id
),
WindowAgg AS (
  SELECT
    ji.*,
    COUNT(*) OVER (PARTITION BY CAST(ji.CreationDate AS date)) AS PostsPerDay,
    MAX(ji.Score) OVER (PARTITION BY CAST(ji.CreationDate AS date)) AS MaxScoreForDay,
    MIN(ji.ViewCount) OVER (PARTITION BY CAST(ji.CreationDate AS date)) AS MinViewsForDay
  FROM JoinedInfo ji
),
CorrelationSub AS (
  SELECT
    w.PostId,
    w.Title,
    w.OwnerUserId,
    w.OwnerDisplayName,
    w.Score,
    w.ViewCount,
    w.CommentCount,
    w.AnswerCount,
    w.FavoriteCount,
    w.CreationDate,
    w.LastActivityDate,
    w.LastEditDate,
    w.LastEditorDisplayName,
    w.LastEditorUserId,
    w.Body,
    w.Tags,
    w.ContentLicense,
    w.OwnerType,
    w.PostsPerDay,
    w.MaxScoreForDay,
    w.MinViewsForDay,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = w.PostId) AS CommentCountTotal,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = w.PostId AND v.VoteTypeId = 2) AS AvgUpvotesFromVotes
  FROM WindowAgg w
)
SELECT
  cs.PostId,
  cs.Title,
  cs.OwnerDisplayName,
  cs.OwnerType,
  cs.Score,
  cs.ViewCount,
  cs.CommentCount,
  cs.AnswerCount,
  cs.FavoriteCount,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.MaxScoreForDay,
  cs.PostsPerDay,
  cs.MinViewsForDay,
  cs.CommentCountTotal,
  cs.AvgUpvotesFromVotes,
  STRING_AGG(t.Tag, ',') AS TagsFlattened,
  COALESCE(oc.Status, 'Open') AS Status
FROM CorrelationSub cs
LEFT JOIN TagSplit t ON cs.PostId = t.PostId
LEFT JOIN OpenVsClosed oc ON cs.PostId = oc.PostId
GROUP BY
  cs.PostId,
  cs.Title,
  cs.OwnerDisplayName,
  cs.OwnerType,
  cs.Score,
  cs.ViewCount,
  cs.CommentCount,
  cs.AnswerCount,
  cs.FavoriteCount,
  cs.CreationDate,
  cs.LastActivityDate,
  cs.MaxScoreForDay,
  cs.PostsPerDay,
  cs.MinViewsForDay,
  cs.CommentCountTotal,
  cs.AvgUpvotesFromVotes,
  COALESCE(oc.Status, 'Open')
ORDER BY cs.CreationDate DESC
LIMIT 200;