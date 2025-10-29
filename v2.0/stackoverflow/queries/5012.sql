-- {"query": "5012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 972}
WITH TrendingPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.Score DESC) AS rn_by_owner
  FROM Posts p
  WHERE p.PostTypeId = 1
),
RecentActivity AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.Tags,
    LAG(p.LastActivityDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate) AS prev_activity
  FROM Posts p
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS rn_tag
  FROM Tags t
  WHERE t.IsModeratorOnly = FALSE
),
UserSummary AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostsCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgesCount
  FROM Users u
),
CrossJoinAgg AS (
  SELECT
    tp.Id AS PostId,
    tp.Title,
    tp.OwnerUserId,
    tp.Score,
    tp.ViewCount,
    tp.Tags,
    ti.Name AS HistoryTypeName,
    v.VoteTypeId,
    v.CreationDate AS VoteDate,
    v.BountyAmount
  FROM TrendingPosts tp
  LEFT JOIN PostHistory ph
    ON ph.PostId = tp.Id
  LEFT JOIN PostHistoryTypes ti
    ON ph.PostHistoryTypeId = ti.Id
  LEFT JOIN Votes v
    ON v.PostId = tp.Id
  WHERE ph.PostHistoryTypeId IN (1, 2, 4, 10, 16) OR v.VoteTypeId IS NOT NULL
),
WindowedStats AS (
  SELECT
    p.Id,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.PostTypeId,
    SUM(p.Score) OVER (PARTITION BY p.PostTypeId) AS SumScoreByType,
    AVG(p.ViewCount) OVER (PARTITION BY p.PostTypeId) AS AvgViewsByType,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.LastActivityDate DESC) AS overall_rank
  FROM Posts p
  WHERE p.LastActivityDate > (CAST('2024-10-01' AS date) - INTERVAL '365 days')
)
SELECT
  tp.Id AS PostId,
  tp.Title,
  tp.CreationDate AS PostCreated,
  tp.OwnerUserId AS OwnerId,
  u.DisplayName AS OwnerDisplayName,
  tp.Score,
  tp.ViewCount,
  tp.Tags,
  (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tp.Id) AS CommentCount,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = tp.Id AND vv.VoteTypeId = 2) AS UpvotesFromVotes,
  (SELECT COUNT(*) FROM Votes vv WHERE vv.PostId = tp.Id AND vv.VoteTypeId = 3) AS DownvotesFromVotes,
  pv.SumScoreByType,
  pv.AvgViewsByType,
  pht.Name AS LastVoteType,
  ph.Comment AS LastHistoryComment,
  ph.CreationDate AS HistoryDate,
  ba.Name AS BadgeName,
  br.TagBased AS IsTagBased
FROM TrendingPosts tp
LEFT JOIN Users u ON u.Id = tp.OwnerUserId
LEFT JOIN WindowedStats pv ON pv.Id = tp.Id
LEFT JOIN PostHistory ph ON ph.PostId = tp.Id
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Votes vt ON vt.PostId = tp.Id
LEFT JOIN Badges ba ON ba.UserId = tp.OwnerUserId
LEFT JOIN Tags t ON t.ExcerptPostId = tp.Id
LEFT JOIN (SELECT Id, Name, TagBased FROM Badges) AS br ON br.Id = ba.Id
WHERE tp.rn_by_owner = 1
ORDER BY tp.ViewCount DESC, tp.Score DESC
LIMIT 100;