-- {"query": "5191.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 993} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.Location,
    u.WebsiteUrl,
    u.EmailHash,
    u.AccountId,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.UpVotes - u.DownVotes DESC, u.CreationDate DESC) AS rn
  FROM Users u
),
TagPopularity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgScore,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesOnTag,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesOnTag
  FROM Tags tg
  JOIN Posts p ON p.Id = tg.WikiPostId OR p.Id = tg.ExcerptPostId
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  CROSS APPLY (SELECT UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName) AS x
  GROUP BY t.TagName
),
ComplexAggregates AS (
  SELECT
    ph.Id AS PostHistoryId,
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.RevisionGUID,
    ph.CreationDate AS RevisionDate,
    ph.UserId AS EditorUserId,
    ph.Comment,
    ph.Text,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    u.DisplayName AS EditorDisplayName
  FROM PostHistory ph
  LEFT JOIN Posts p ON p.Id = ph.PostId
  LEFT JOIN Users u ON u.Id = ph.UserId
  WHERE ph.CreationDate >= NOW() - INTERVAL '60 days'
)
SELECT
  -- Outer join demonstration: get recent posts with editor info if available
  r.PostId,
  r.Title,
  r.PostTypeId,
  r.OwnerUserId,
  o.DisplayName AS OwnerDisplayName,
  r.CreationDate AS PostCreated,
  r.LastActivityDate,
  r.Tags,
  r.ViewCount,
  r.Score,
  r.CommentCount,
  r.AnswerCount,
  -- Window function: rank recent posts by score within PostType
  ROW_NUMBER() OVER (PARTITION BY r.PostTypeId ORDER BY r.Score DESC, r.LastActivityDate DESC) AS TypeRank,
  -- Subquery correlation: total edits for this post from PostHistory
  (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = r.PostId) AS EditCount,
  -- Set operator: union with a synthetic row to benchmark
  t.TagName,
  t.TagCount,
  t.AvgScore,
  t.UpvotesOnTag,
  t.DownvotesOnTag
FROM RecentActivePosts r
LEFT JOIN Users o ON o.Id = r.OwnerUserId
LEFT JOIN TopUsers tu ON tu.UserId = o.Id
LEFT JOIN (
  SELECT DISTINCT ON (TagName) TagName, TagCount, AvgScore, UpvotesOnTag, DownvotesOnTag
  FROM TagPopularity
  ORDER BY TagName, TagCount DESC
) t ON true
UNION ALL
SELECT
  NULL AS PostId,
  NULL AS Title,
  NULL AS PostTypeId,
  NULL AS OwnerUserId,
  NULL AS OwnerDisplayName,
  NULL AS PostCreated,
  NULL AS LastActivityDate,
  NULL AS Tags,
  NULL AS ViewCount,
  NULL AS Score,
  NULL AS CommentCount,
  NULL AS AnswerCount,
  NULL AS TypeRank,
  NULL AS EditCount,
  tg.TagName,
  tg.TagCount,
  tg.AvgScore,
  tg.UpvotesOnTag,
  tg.DownvotesOnTag
FROM TagPopularity tg
ORDER BY PostCreated NULLS LAST, TypeRank NULLS LAST
LIMIT 200;