-- {"query": "5138.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 892} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
TopUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    COUNT(v.Id) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCast,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY u.Id
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore
  FROM Tags t
  LEFT JOIN Posts p ON p.Id = t.WikiPostId OR p.Id = t.ExcerptPostId
  GROUP BY t.TagName
),
CorrelatedPosts AS (
  SELECT
    rp.Id AS RelatedPostId,
    rp.Title AS RelatedTitle,
    rp.OwnerUserId AS RelatedOwner,
    rp.Score AS RelatedScore,
    rp.ViewCount AS RelatedViews,
    p.Id AS PostId,
    p.Title AS Title,
    p.OwnerUserId AS PostOwner,
    p.Score AS PostScore,
    p.ViewCount AS PostViews,
    p.LastActivityDate AS PostLastActivity
  FROM RecentActivePosts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Posts rp ON rp.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId IN (1, 3) -- Linked or Duplicate relations
),
WindowedStats AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn_by_owner,
    RANK() OVER (ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rank_by_activity
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
ComplexFilters AS (
  SELECT
    w.Id AS PostId,
    w.Title,
    w.OwnerUserId,
    w.Score,
    w.ViewCount,
    w.LastActivityDate,
    cf.TotalVotes,
    cf.UpvotesCast,
    cf.DownvotesCast,
    uv.DisplayName AS OwnerDisplayName,
    c.TotalComments
  FROM WindowedStats w
  LEFT JOIN TopUsers cf ON cf.UserId = w.OwnerUserId
  LEFT JOIN Users uv ON uv.Id = w.OwnerUserId
  LEFT JOIN (
    SELECT p.Id AS PostId, p.CommentCount AS TotalComments
    FROM Posts p
  ) c ON c.PostId = w.Id
  WHERE w.rn_by_owner = 1
)
SELECT
  cp.PostId,
  cp.Title AS PostTitle,
  cp.OwnerUserId,
  cp.OwnerDisplayName,
  cp.Score,
  cp.ViewCount,
  cp.LastActivityDate,
  cp.TotalVotes,
  cp.UpvotesCast,
  cp.DownvotesCast,
  ct.TagName,
  ta.TagCount,
  ta.AvgPostScore,
  w.rank_by_activity,
  w.rn_by_owner
FROM ComplexFilters cp
LEFT JOIN TagActivity ta ON ta.TagName = ANY(string_to_array(substring(cp.Title, 1, 1000), ' '))
LEFT JOIN WindowedStats w ON w.Id = cp.PostId
ORDER BY cp.LastActivityDate DESC NULLS LAST, cp.Score DESC, cp.ViewCount DESC
LIMIT 200;