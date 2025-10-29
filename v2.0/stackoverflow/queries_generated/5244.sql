-- {"query": "5244.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1319} 
WITH
-- Top 5 active users by reputation, with a windowed ranking
ActiveUsers AS (
  SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
),
-- Posts with a recent activity window
RecentPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount
  FROM Posts p
  WHERE p.LastActivityDate >= NOW() - INTERVAL '30 days'
),
-- Complex metrics per post using correlated subqueries and window functions
PostMetrics AS (
  SELECT
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.ViewCount,
    rp.Score,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.CommentCount,
    rp.FavoriteCount,
    -- Number of comments on the post
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentTotal,
    -- Number of edits from PostHistory (types 4/5/6/10/11/12/13/14/16/17)
    (SELECT COUNT(*) FROM PostHistory ph
     WHERE ph.PostId = rp.Id
       AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,14,16,17,38,37,50)) AS EditCount,
    -- Sum of upvotes minus downvotes for the post (using Votes where type = 2 or 3)
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpVotesAgg,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) AS DownVotesAgg,
    -- Distinct linked/duplicate relationships
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.Id) AS LinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = rp.Id) AS ReferencedByCount,
    -- Flag: is community owned at some point
    EXISTS (SELECT 1 FROM PostHistory ph
            WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId = 16) AS IsCommunityOwned
  FROM RecentPosts rp
),
-- Compute a composite benchmarking score using multiple signals
BenchmarkScore AS (
  SELECT
    pm.PostId,
    pm.PostTypeId,
    pm.OwnerUserId,
    pm.Title,
    pm.ViewCount,
    pm.Score,
    pm.CommentTotal,
    pm.EditCount,
    pm.UpVotesAgg,
    pm.DownVotesAgg,
    pm.LinkCount,
    pm.ReferencedByCount,
    pm.IsCommunityOwned,
    -- Normalized components
    (CASE WHEN pm.ViewCount > 0 THEN (pm.ViewCount) / 1.0 ELSE 0 END) AS S_view,
    (CASE WHEN pm.EditCount > 0 THEN (pm.EditCount) / 1.0 ELSE 0 END) AS S_edits,
    (CASE WHEN pm.UpVotesAgg > 0 THEN (pm.UpVotesAgg) / 1.0 ELSE 0 END) AS S_up,
    (CASE WHEN pm.DownVotesAgg > 0 THEN (pm.DownVotesAgg) / 1.0 ELSE 0 END) AS S_down,
    (CASE WHEN pm.LinkCount > 0 THEN (pm.LinkCount) / 1.0 ELSE 0 END) AS S_links,
    (CASE WHEN pm.ReferencedByCount > 0 THEN (pm.ReferencedByCount) / 1.0 ELSE 0 END) AS S_refby,
    CASE WHEN pm.IsCommunityOwned THEN 1 ELSE 0 END AS IsCommOwned,
    -- Final composite score
    (COALESCE(pm.ViewCount,0) * 0.2
     + COALESCE(pm.Score,0) * 0.5
     + COALESCE(pm.CommentTotal,0) * 0.3
     + COALESCE(pm.EditCount,0) * 0.4
     + COALESCE(pm.UpVotesAgg,0) * 0.6
     - COALESCE(pm.DownVotesAgg,0) * 0.2
     + COALESCE(pm.LinkCount,0) * 0.3
     + COALESCE(pm.ReferencedByCount,0) * 0.2
     + IsCommunityOwned * 2.0) AS BenchmarkValue
  FROM PostMetrics pm
),
-- Final aggregation: top performers by composite score, with outer join to Users to fetch profile details
TopBenchmark AS (
  SELECT
    bs.PostId,
    bs.PostTypeId,
    bs.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.AccountId,
    bs.Title,
    bs.ViewCount,
    bs.Score,
    bs.CommentTotal,
    bs.EditCount,
    bs.UpVotesAgg,
    bs.DownVotesAgg,
    bs.LinkCount,
    bs.ReferencedByCount,
    bs.IsCommOwned,
    bs.BenchmarkValue
  FROM BenchmarkScore bs
  LEFT JOIN Users u ON u.Id = bs.OwnerUserId
  ORDER BY bs.BenchmarkValue DESC
  LIMIT 100
)
SELECT
  t.OwnerDisplayName,
  t.Reputation,
  t.Title,
  t.ViewCount,
  t.Score,
  t.CommentTotal,
  t.EditCount,
  t.UpVotesAgg,
  t.DownVotesAgg,
  t.LinkCount,
  t.ReferencedByCount,
  t.IsCommOwned,
  t.BenchmarkValue
FROM TopBenchmark t
ORDER BY t.BenchmarkValue DESC, t.Reputation DESC, t.OwnerDisplayName;