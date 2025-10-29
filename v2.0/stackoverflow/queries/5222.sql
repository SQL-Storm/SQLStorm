-- {"query": "5222.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 698}
WITH
RecentTopPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    AND p.PostTypeId IN (1, 2)
),
TrendingTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId,
    t.IsModeratorOnly
  FROM Tags t
  WHERE COALESCE(t.IsModeratorOnly, FALSE) = FALSE
),
ComplexFilter AS (
  SELECT
    r.*,
    v.VoteTypeId AS _vote_votetypeid
  FROM RecentTopPosts r
  LEFT JOIN PostLinks pl ON pl.PostId = r.PostId
  LEFT JOIN Votes v ON v.PostId = r.PostId
  INNER JOIN TrendingTags tt ON (tt.ExcerptPostId = r.PostId OR tt.WikiPostId = r.PostId)
  WHERE
    (r.Score > 0 OR r.ViewCount > 1000)
    AND (v.VoteTypeId IS NULL OR v.VoteTypeId IN (2, 12, 16))
    AND (r.LastActivityDate IS NOT NULL)
),
Aggs AS (
  SELECT
    cp.PostId,
    cp.Title,
    cp.OwnerUserId,
    cp.OwnerDisplayName,
    cp.Reputation,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.Score,
    cp.ViewCount,
    cp.CommentCount,
    cp.FavoriteCount,
    cp.ContentLicense,
    COUNT(*) OVER (PARTITION BY cp.OwnerUserId) AS PostsByAuthor,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.OwnerUserId) AS UpvotesByAuthor,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY cp.OwnerUserId) AS DownvotesByAuthor,
    -- compute distinct tags per post via subquery aggregation instead of DISTINCT inside window STRING_AGG
    tagagg.AllTags,
    cp.rn
  FROM ComplexFilter cp
  LEFT JOIN Votes v ON v.PostId = cp.PostId
  LEFT JOIN Tags tt ON (tt.ExcerptPostId = cp.PostId OR tt.WikiPostId = cp.PostId)
  LEFT JOIN (
    SELECT
      t2.ExcerptPostId AS PostId,
      STRING_AGG(t2.TagName, ',') AS AllTags
    FROM (
      SELECT DISTINCT
        COALESCE(ExcerptPostId, WikiPostId) AS ExcerptPostId,
        TagName
      FROM Tags
    ) t2
    GROUP BY t2.ExcerptPostId
  ) tagagg ON tagagg.PostId = cp.PostId
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  Reputation,
  CreationDate,
  LastActivityDate,
  Score,
  ViewCount,
  CommentCount,
  FavoriteCount,
  ContentLicense,
  PostsByAuthor,
  UpvotesByAuthor,
  DownvotesByAuthor,
  AllTags
FROM Aggs
WHERE rn <= 5
ORDER BY LastActivityDate DESC, Score DESC;