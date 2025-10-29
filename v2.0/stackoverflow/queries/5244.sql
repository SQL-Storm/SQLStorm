WITH
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
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
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
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentTotal,
    (SELECT COUNT(*) FROM PostHistory ph
     WHERE ph.PostId = rp.Id
       AND ph.PostHistoryTypeId IN (4,5,6,10,11,12,13,14,16,17,38,37,50)) AS EditCount,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 2) AS UpVotesAgg,
    (SELECT COALESCE(SUM(v.BountyAmount),0) FROM Votes v WHERE v.PostId = rp.Id AND v.VoteTypeId = 3) AS DownVotesAgg,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.Id) AS LinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.RelatedPostId = rp.Id) AS ReferencedByCount,
    CASE WHEN EXISTS (SELECT 1 FROM PostHistory ph
            WHERE ph.PostId = rp.Id AND ph.PostHistoryTypeId = 16) THEN 1 ELSE 0 END AS IsCommunityOwned
  FROM RecentPosts rp
),
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
    (CASE WHEN pm.ViewCount > 0 THEN (pm.ViewCount) / 1.0 ELSE 0 END) AS S_view,
    (CASE WHEN pm.EditCount > 0 THEN (pm.EditCount) / 1.0 ELSE 0 END) AS S_edits,
    (CASE WHEN pm.UpVotesAgg > 0 THEN (pm.UpVotesAgg) / 1.0 ELSE 0 END) AS S_up,
    (CASE WHEN pm.DownVotesAgg > 0 THEN (pm.DownVotesAgg) / 1.0 ELSE 0 END) AS S_down,
    (CASE WHEN pm.LinkCount > 0 THEN (pm.LinkCount) / 1.0 ELSE 0 END) AS S_links,
    (CASE WHEN pm.ReferencedByCount > 0 THEN (pm.ReferencedByCount) / 1.0 ELSE 0 END) AS S_refby,
    pm.IsCommunityOwned AS IsCommOwned,
    (COALESCE(pm.ViewCount,0) * 0.2
     + COALESCE(pm.Score,0) * 0.5
     + COALESCE(pm.CommentTotal,0) * 0.3
     + COALESCE(pm.EditCount,0) * 0.4
     + COALESCE(pm.UpVotesAgg,0) * 0.6
     - COALESCE(pm.DownVotesAgg,0) * 0.2
     + COALESCE(pm.LinkCount,0) * 0.3
     + COALESCE(pm.ReferencedByCount,0) * 0.2
     + (CASE WHEN pm.IsCommunityOwned <> 0 THEN 2.0 ELSE 0 END)
    ) AS BenchmarkValue
  FROM PostMetrics pm
),
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