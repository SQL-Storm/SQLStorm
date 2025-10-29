-- {"query": "5358.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 778} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.LastActivityDate,
    p.Tags,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(a.DisplayName, u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC NULLS LAST,
        p.ViewCount DESC NULLS LAST,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Users a ON p.LastEditorUserId = a.Id
  WHERE p.PostTypeId IN (1,2)
),
filtered AS (
  SELECT
    rp.*,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.Id) AS UpvotesOnPost,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY rp.Id) AS DownvotesOnPost,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id) AS CommentCountExact,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.Id AND pl.LinkTypeId = 1) AS LinkedPosts
  FROM ranked_posts rp
  LEFT JOIN Votes v ON v.PostId = rp.Id
),
cte AS (
  SELECT
    f.Id,
    f.Title,
    f.PostTypeId,
    f.CreationDate,
    f.OwnerUserId,
    f.ViewCount,
    f.Score,
    f.LastActivityDate,
    f.Tags,
    f.CommentCount AS CommentCountFromPost,
    f.FavoriteCount,
    f.OwnerDisplayName,
    f.rn,
    f.UpvotesOnPost,
    f.DownvotesOnPost,
    f.CommentCountExact,
    f.LinkedPosts
  FROM filtered f
  WHERE f.rn = 1
),
windowed AS (
  SELECT
    c.*,
    SUM(c.ViewCount) OVER (PARTITION BY c.PostTypeId ORDER BY c.CreationDate) AS RunningViewsForType
  FROM cte c
),
outer_join_example AS (
  SELECT
    w.*,
    ll.Id AS LinkedPostId,
    ll.Title AS LinkedPostTitle
  FROM windowed w
  LEFT JOIN PostLinks pl ON w.Id = pl.PostId AND pl.LinkTypeId = 1
  LEFT JOIN Posts ll ON pl.RelatedPostId = ll.Id
),
final AS (
  SELECT
    oje.Id,
    oje.Title,
    oje.PostTypeId,
    oje.CreationDate,
    oje.OwnerDisplayName,
    oje.ViewCount,
    oje.Score,
    oje.LastActivityDate,
    oje.Tags,
    oje.CommentCountFromPost,
    oje.FavoriteCount,
    oje.RunningViewsForType,
    oje.LinkedPosts,
    oje.LinkedPostId,
    oje.LinkedPostTitle
  FROM outer_join_example oje
  WHERE
    (oje.PostTypeId = 1 AND oje.Score > 0 AND oje.ViewCount > 50)
    OR
    (oje.PostTypeId = 2 AND oje.UpvotesOnPost - oje.DownvotesOnPost > 0)
)
SELECT
  *
FROM final
ORDER BY
  LastActivityDate DESC
OFFSET 0 ROWS
FETCH NEXT 200 ROWS ONLY;