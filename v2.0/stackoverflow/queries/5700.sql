-- {"query": "5700.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 604}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    p.CommentCount,
    COALESCE(ud.Reputation, 0) AS OwnerReputation,
    COALESCE(au.Reputation, 0) AS LastEditorReputation,
    AVG(CASE WHEN v.VoteTypeId = 2 THEN 1.0 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpvoteRatio
  FROM Posts p
  LEFT JOIN Users ud ON p.OwnerUserId = ud.Id
  LEFT JOIN Users au ON p.LastEditorUserId = au.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1 -- questions only
),
cte_tags AS (
  SELECT
    rp.PostId,
    unnest(string_to_array(substring(rp.Tags FROM 2 FOR (char_length(rp.Tags)-2)), '><')) AS Tag
  FROM ranked_posts rp
  WHERE rp.Tags IS NOT NULL AND rp.Tags <> ''
),
expanded AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerReputation,
    rp.LastEditorReputation,
    rp.Score,
    rp.ViewCount,
    rp.FavoriteCount,
    rp.CommentCount,
    rp.UpvoteRatio,
    t.Tag,
    ROW_NUMBER() OVER (PARTITION BY rp.PostId ORDER BY rp.CreationDate) AS tag_seq
  FROM ranked_posts rp
  LEFT JOIN cte_tags t ON rp.PostId = t.PostId
)
SELECT
  e.PostId,
  e.Title,
  e.CreationDate,
  e.LastActivityDate,
  e.OwnerUserId,
  e.OwnerReputation,
  e.LastEditorReputation,
  e.Score,
  e.ViewCount,
  e.FavoriteCount,
  e.CommentCount,
  e.UpvoteRatio,
  e.Tag,
  e.tag_seq
FROM expanded e
UNION ALL
SELECT
  rp.PostId,
  rp.Title,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.OwnerUserId,
  rp.OwnerReputation,
  rp.LastEditorReputation,
  rp.Score,
  rp.ViewCount,
  rp.FavoriteCount,
  rp.CommentCount,
  rp.UpvoteRatio,
  NULL AS Tag,
  NULL AS tag_seq
FROM ranked_posts rp
WHERE rp.Tags IS NULL OR rp.Tags = ''
ORDER BY LastActivityDate DESC, Score DESC NULLS LAST, tag_seq ASC NULLS LAST
LIMIT 200;