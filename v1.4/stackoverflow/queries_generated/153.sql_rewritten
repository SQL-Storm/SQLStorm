-- {"query": "153.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2823} 
WITH
  -- recent posts by type with a deterministic ranking
  recent_posts AS (
    SELECT
      p.Id,
      p.PostTypeId,
      p.Title,
      p.Tags,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.OwnerUserId,
      ROW_NUMBER() OVER (
        PARTITION BY p.PostTypeId
        ORDER BY
          p.Score DESC NULLS LAST,
          p.ViewCount DESC NULLS LAST,
          p.CreationDate DESC
      ) AS rn
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '90 days'
  ),
  -- aggregate votes per post (upvotes minus downvotes as a net metric)
  vote_stats AS (
    SELECT
      v.PostId,
      COUNT(*) AS VoteCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
      SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS UpOrDown
    FROM Votes v
    GROUP BY v.PostId
  ),
  -- number of comments per post
  comment_counts AS (
    SELECT
      c.PostId,
      COUNT(*) AS CommentCount
    FROM Comments c
    GROUP BY c.PostId
  ),
  -- counts of badges per post owner (for enrichment and NULL-safe handling)
  owner_badge_counts AS (
    SELECT
      b.UserId,
      COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId
  ),
  -- top linked/related posts per post (count by LinkTypeId)
  post_links_summary AS (
    SELECT
      pl.PostId,
      COUNT(*) AS LinkCount
    FROM PostLinks pl
    GROUP BY pl.PostId
  ),
  -- a derived dataset combining the heavy hitters with user info and related metrics
  enriched AS (
    SELECT
      rp.Id,
      rp.PostTypeId,
      rp.Title,
      rp.Tags,
      rp.CreationDate,
      rp.Score,
      rp.ViewCount,
      rp.OwnerUserId,
      rp.rn,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation,
      COALESCE(oc.BadgeCount, 0) AS OwnerBadgeCount,
      COALESCE(vc.UpVotes, 0) AS UpVotes,
      COALESCE(vc.DownVotes, 0) AS DownVotes,
      COALESCE(cc.CommentCount, 0) AS CommentCount,
      COALESCE(plt.LinkCount, 0) AS LinkCount,
      (COALESCE(vc.UpVotes,0) - COALESCE(vc.DownVotes,0)) AS NetVoteBalance,
      (COALESCE(rp.Score,0) * 2
       + COALESCE(rp.ViewCount,0) / 10
       + COALESCE(cc.CommentCount,0)) AS EngagementScore
    FROM recent_posts rp
    LEFT JOIN Users u ON u.Id = rp.OwnerUserId
    LEFT JOIN vote_stats vc ON vc.PostId = rp.Id
    LEFT JOIN comment_counts cc ON cc.PostId = rp.Id
    LEFT JOIN owner_badge_counts oc ON oc.UserId = rp.OwnerUserId
    LEFT JOIN post_links_summary plt ON plt.PostId = rp.Id
    WHERE rp.rn <= 100
  ),
  -- a correlated subquery computing a dynamic tag relevance score per post (string and NULL-safe)
  tag_relevance AS (
    SELECT
      e.Id,
      CASE
        WHEN e.Tags IS NULL THEN 0.0
        ELSE (CASE WHEN POSITION('<' IN e.Tags) > 0 THEN 1.0 ELSE 0.0 END)
      END AS TagRelevanceFlag
    FROM enriched e
  ),
  -- final result: produce a set that could be used for benchmarking diverse operators
  grouped AS (
    SELECT
      e.Id,
      e.PostTypeId,
      e.Title,
      e.Tags,
      e.CreationDate,
      e.Score,
      e.ViewCount,
      e.OwnerUserId,
      e.OwnerDisplayName,
      e.Reputation,
      e.OwnerBadgeCount,
      e.UpVotes,
      e.DownVotes,
      e.CommentCount,
      e.LinkCount,
      e.NetVoteBalance,
      e.EngagementScore,
      tr.TagRelevanceFlag
    FROM enriched e
    LEFT JOIN tag_relevance tr ON tr.Id = e.Id
  ),
  -- concatenate two datasets with a UNION ALL to exercise set operations
  final_dataset AS (
    SELECT
      Id, PostTypeId, Title, Tags, CreationDate, Score, ViewCount,
      OwnerUserId, OwnerDisplayName, Reputation, OwnerBadgeCount,
      UpVotes, DownVotes, CommentCount, LinkCount, NetVoteBalance, EngagementScore,
      TagRelevanceFlag
    FROM grouped
    UNION ALL
    SELECT
      NULL AS Id,
      NULL AS PostTypeId,
      'BenchmarkNote' AS Title,
      NULL AS Tags,
      cast('2024-10-01 12:34:56' as timestamp) AS CreationDate,
      0 AS Score,
      0 AS ViewCount,
      NULL AS OwnerUserId,
      NULL AS OwnerDisplayName,
      0 AS Reputation,
      0 AS OwnerBadgeCount,
      0 AS UpVotes,
      0 AS DownVotes,
      0 AS CommentCount,
      0 AS LinkCount,
      0 AS NetVoteBalance,
      0 AS EngagementScore,
      0 AS TagRelevanceFlag
  )
SELECT
  Id,
  PostTypeId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  OwnerDisplayName,
  Reputation,
  OwnerBadgeCount,
  UpVotes,
  DownVotes,
  CommentCount,
  LinkCount,
  NetVoteBalance,
  EngagementScore,
  TagRelevanceFlag
FROM final_dataset
ORDER BY EngagementScore DESC NULLS LAST
LIMIT 300;