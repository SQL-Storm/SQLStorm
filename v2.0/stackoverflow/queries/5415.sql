WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days'
),
growth AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.ViewCount,
    q.Score,
    q.Tags,
    u.DisplayName AS Owner,
    q.LastActivityDate,
    q.AcceptedAnswerId,
    q.CommentCount,
    q.FavoriteCount,
    COUNT(a.Id) AS AnswerCount,
    AVG(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS AvgBountyOnActions
  FROM recent_questions q
  LEFT JOIN PostLinks pl ON pl.PostId = q.PostId
  LEFT JOIN Posts a ON a.ParentId = q.PostId AND a.PostTypeId = 2
  LEFT JOIN Votes v ON v.PostId = q.PostId AND v.VoteTypeId = 2
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  GROUP BY
    q.PostId, q.Title, q.CreationDate, q.ViewCount, q.Score, q.Tags,
    u.DisplayName, q.LastActivityDate, q.AcceptedAnswerId, q.CommentCount, q.FavoriteCount
),
complex AS (
  SELECT
    g.PostId,
    g.Title,
    g.Owner,
    g.CreationDate,
    g.LastActivityDate,
    g.ViewCount,
    g.Score,
    g.Tags,
    g.CommentCount,
    g.FavoriteCount,
    g.AnswerCount,
    COALESCE(b.Count, 0) AS TagMentions,
    CASE
      WHEN g.Score > 20 THEN 'hot'
      WHEN g.LastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '14 days' THEN 'active'
      ELSE 'idle'
    END AS status
  FROM growth g
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS Count
    FROM Posts t
    WHERE t.ParentId = g.PostId
      AND t.PostTypeId = 2
  ) b ON true
  LEFT JOIN Tags t ON t.ExcerptPostId = g.PostId OR t.WikiPostId = g.PostId
  WHERE g.ViewCount >= 100
),
-- helper to split tag string into rows; adjust delimiter and escaping as needed
unnested_tags AS (
  SELECT
    c.PostId,
    TRIM(tag) AS TagName
  FROM complex c,
  LATERAL (
    SELECT regexp_split_to_table(c.Tags, E'\\\\|') AS tag
  ) s
  WHERE c.Tags IS NOT NULL AND c.Tags <> ''
)
SELECT
  c.PostId,
  c.Title,
  c.Owner,
  c.CreationDate,
  c.LastActivityDate,
  c.ViewCount,
  c.Score,
  STRING_AGG(DISTINCT ut.TagName, ',') AS TagsList,
  c.CommentCount,
  c.FavoriteCount,
  c.AnswerCount,
  c.TagMentions,
  c.status
FROM complex c
LEFT JOIN unnested_tags ut ON ut.PostId = c.PostId
GROUP BY
  c.PostId, c.Title, c.Owner, c.CreationDate, c.LastActivityDate,
  c.ViewCount, c.Score, c.Tags, c.CommentCount, c.FavoriteCount,
  c.AnswerCount, c.TagMentions, c.status
ORDER BY c.LastActivityDate DESC, c.Score DESC
LIMIT 200;