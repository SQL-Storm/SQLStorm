-- {"query": "5217.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 903} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.LastEditorUserId,
    p.OwnerDisplayName,
    p.ContentLicense,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(b.Class, 0) AS badge_class,
    STRING_AGG(COALESCE(vt.Name, ''), ',') FILTER (WHERE v.VoteTypeId IS NOT NULL) AS vote_types
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId IN (1, 2) -- questions and answers
  GROUP BY
    p.Id, p.PostTypeId, p.Title, p.Body, p.CreationDate, p.Score, p.ViewCount,
    p.OwnerUserId, p.Tags, p.AnswerCount, p.CommentCount, p.FavoriteCount,
    p.LastActivityDate, p.LastEditDate, p.LastEditorUserId, p.OwnerDisplayName,
    p.ContentLicense, u.Reputation, b.Class
),
recent_activity AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.ViewCount,
    rp.Score,
    rp.AnswerCount,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.LastActivityDate,
    rp.Tags,
    rp.vote_types,
    ROW_NUMBER() OVER (
      PARTITION BY rp.OwnerUserId
      ORDER BY rp.LastActivityDate DESC, rp.Score DESC, rp.ViewCount DESC
    ) AS rn_by_owner
  FROM ranked_posts rp
  LEFT JOIN Posts p ON rp.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
  WHERE rp.LastActivityDate IS NOT NULL
),
complex_derived AS (
  SELECT
    ra.PostId,
    ra.Title,
    ra.OwnerUserId,
    ra.OwnerDisplayName,
    ra.OwnerReputation,
    ra.ViewCount,
    ra.Score,
    ra.AnswerCount,
    ra.CommentCount,
    ra.FavoriteCount,
    ra.LastActivityDate,
    ra.Tags,
    ra.vote_types,
    -- Example complex expression: time since creation in hours
    EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - (SELECT CreationDate FROM Posts WHERE Id = ra.PostId))) / 3600 AS hours_since_creation,
    -- correlated subquery: count of related posts that link to this post
    (SELECT COUNT(*) FROM PostLinks pl2 WHERE pl2.RelatedPostId = ra.PostId) AS linked_posts_count,
    -- window function over recent activity per owner will be simulated in outer query
    CASE
      WHEN ra.OwnerReputation > 10000 THEN 'legend'
      WHEN ra.OwnerReputation > 1000 THEN 'guru'
      ELSE 'member'
    END AS member_band
  FROM recent_activity ra
  WHERE ra.rn_by_owner <= 5
)
SELECT
  c.PostId,
  c.Title,
  c.OwnerDisplayName,
  c.OwnerReputation,
  c.ViewCount,
  c.Score,
  c.AnswerCount,
  c.CommentCount,
  c.FavoriteCount,
  c.LastActivityDate,
  c.Tags,
  c.vote_types,
  c.hours_since_creation,
  c.linked_posts_count,
  c.member_band
FROM complex_derived c
LEFT JOIN LATERAL (
  SELECT
    AVG(p.Score) AS avg_post_score_by_owner
  FROM Posts p
  WHERE p.OwnerUserId = c.OwnerUserId
) AS s ON TRUE
ORDER BY c.LastActivityDate DESC, c.hours_since_creation ASC
LIMIT 200;