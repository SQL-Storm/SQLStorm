-- {"query": "5286.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 983} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    p.AcceptedAnswerId,
    p.ParentId,
    p.Body,
    p.LastEditorUserId,
    p.LastEditDate,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    u.AccountId,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    -- compute a dynamic score by combining post score, views, and reputation with null-safe ops
    COALESCE(p.Score,0) * 1.0
    + COALESCE(p.ViewCount,0) * 0.01
    + COALESCE(u.Reputation,0) * 0.0001 AS composite_score
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
activity_windows AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.PostTypeId,
    rp.OwnerUserId,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.Body,
    rp.LastEditorUserId,
    rp.LastEditDate,
    rp.ContentLicense,
    rp.Reputation,
    rp.DisplayName,
    rp.Location,
    rp.AccountId,
    rp.Views,
    rp.UpVotes,
    rp.DownVotes,
    rp.UserCreationDate,
    rp.UserLastAccessDate,
    rp.composite_score,
    -- windowed metrics
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.Id) AS UpvotesForPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.Id) AS DownvotesForPost,
    MAX(v.CreationDate) OVER (PARTITION BY rp.Id) AS LastVoteDate
  FROM ranked_posts rp
  LEFT JOIN Votes v ON v.PostId = rp.Id
),
enriched AS (
  SELECT
    aw.*,
    -- correlated subquery: count distinct tags in the Tags field for an extra metric
    (
      SELECT COUNT(*) 
      FROM unnest(string_to_array(substr(aw.Tags, 2, length(aw.Tags)-2), '><')) AS t
    ) AS TagCount
  FROM activity_windows aw
),
final as (
  SELECT
    e.*,
    -- an outer join example: include possible related posts (duplicates or linked) for benchmarking
    pl.RelatedPostId,
    lt.Name AS LinkTypeName
  FROM enriched e
  LEFT JOIN PostLinks pl ON pl.PostId = e.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE
    -- complicated predicate with NULL logic and expressions
    (e.PostTypeId = 1 AND (e.Score IS NULL OR e.Score > 0))
    OR
    (e.PostTypeId IN (2,7) AND (e.Body IS NOT NULL OR e.Title IS NOT NULL))
    -- include some NULL-safe date bound
    AND (e.CreationDate >= COALESCE((SELECT MIN(CreationDate) FROM Posts), '2000-01-01') )
)
SELECT
  f.Id,
  f.Title,
  f.PostTypeId,
  f.OwnerUserId,
  f.CreationDate,
  f.LastActivityDate,
  f.Score,
  f.ViewCount,
  f.Tags,
  f.CommentCount,
  f.FavoriteCount,
  f.AcceptedAnswerId,
  f.ParentId,
  f.Body,
  f.LastEditorUserId,
  f.LastEditDate,
  f.ContentLicense,
  f.Reputation,
  f.DisplayName,
  f.Location,
  f.AccountId,
  f.Views,
  f.UpVotes,
  f.DownVotes,
  f.UserCreationDate,
  f.UserLastAccessDate,
  f.composite_score,
  f.UpvotesForPost,
  f.DownvotesForPost,
  f.LastVoteDate,
  f.TagCount,
  f.RelatedPostId,
  f.LinkTypeName
FROM final f
ORDER BY f.composite_score DESC NULLS LAST
LIMIT 100;