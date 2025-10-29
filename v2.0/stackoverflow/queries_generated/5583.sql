-- {"query": "5583.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1001} 
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.ParentId,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    -- window: rank posts by activity within 30-day moving window
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.LastActivityDate DESC, p.Score DESC, p.ViewCount DESC
    ) AS rn_by_activity,
    -- dense_rank across posts for recency
    DENSE_RANK() OVER (
      ORDER BY p.CreationDate DESC
    ) AS recency_rank
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1,2,5) -- focus on Questions and Answers and TagWiki
),
CorrelatedStats AS (
  SELECT
    r.PostId,
    r.PostTypeId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.ParentId,
    r.AcceptedAnswerId,
    r.CommentCount,
    r.FavoriteCount,
    r.ContentLicense,
    r.Reputation,
    r.DisplayName,
    r.Location,
    r.Views,
    r.UpVotes,
    r.DownVotes,
    r.AccountId,
    r.rn_by_activity,
    r.recency_rank,
    -- correlated subquery: count of comments for this post with non-null UserId
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = r.PostId AND c.UserId IS NOT NULL) AS CommentersCount,
    -- join to Tag info: number of related posts linked as duplicates
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = r.PostId AND pl.LinkTypeId = 3) AS DuplicateCount
  FROM RankedPosts r
),
Aggregated AS (
  SELECT
    cs.PostId,
    cs.PostTypeId,
    cs.Title,
    cs.Tags,
    cs.CreationDate,
    cs.Score,
    cs.ViewCount,
    cs.OwnerUserId,
    cs.LastActivityDate,
    cs.ParentId,
    cs.AcceptedAnswerId,
    cs.CommentCount,
    cs.FavoriteCount,
    cs.ContentLicense,
    cs.Reputation,
    cs.DisplayName,
    cs.Location,
    cs.Views,
    cs.UpVotes,
    cs.DownVotes,
    cs.AccountId,
    cs.rn_by_activity,
    cs.recency_rank,
    cs.CommentersCount,
    cs.DuplicateCount,
    -- compute a heavy expression: composite score with NULL-safe handling
    (cs.Score + COALESCE(cs.ViewCount,0) * 0.1
     + COALESCE(cs.CommentersCount,0) * 2
     + CASE WHEN cs.Location IS NOT NULL THEN 1 ELSE 0 END) AS CompositeScore,
    -- complex predicate: include only posts with positive composite score and at least one view
    CASE
      WHEN (cs.Score + COALESCE(cs.ViewCount,0) * 0.1) > 0 THEN TRUE
      ELSE FALSE
    END AS IsPromotable
  FROM CorrelatedStats cs
)
SELECT
  a.PostId,
  a.PostTypeId,
  a.Title,
  a.Tags,
  a.CreationDate,
  a.Score,
  a.ViewCount,
  a.OwnerUserId,
  a.LastActivityDate,
  a.ParentId,
  a.AcceptedAnswerId,
  a.CommentCount,
  a.FavoriteCount,
  a.ContentLicense,
  a.Reputation,
  a.DisplayName,
  a.Location,
  a.Views,
  a.UpVotes,
  a.DownVotes,
  a.AccountId,
  a.rn_by_activity,
  a.recency_rank,
  a.CommentersCount,
  a.DuplicateCount,
  a.CompositeScore,
  a.IsPromotable
FROM Aggregated a
WHERE a.IsPromotable = TRUE
  AND a.ViewCount > 0
  -- outer join to include a bit more contextual data: last editor details if any
  LEFT JOIN Posts p2 ON a.PostId = p2.Id
  LEFT JOIN Users le ON p2.LastEditorUserId = le.Id
ORDER BY a.CompositeScore DESC, a.LastActivityDate DESC
LIMIT 100;