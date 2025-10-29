-- {"query": "5956.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1002} 
WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    ROW_NUMBER() OVER (
      PARTITION BY date_trunc('month', p.CreationDate)
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn_in_month
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- questions
    AND p.ClosedDate IS NULL
),
popular_tags AS (
  SELECT
    t.TagName,
    COUNT(*) AS tag_post_count,
    SUM(p.Score) AS score_sum,
    AVG(p.ViewCount) AS avg_views
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
),
recent_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    v.VoteTypeId,
    v.UserId,
    vt.Name AS VoteTypeName,
    ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY v.CreationDate DESC) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.PostTypeId = 1
),
correlated_subselect AS (
  SELECT
    q.PostId,
    q.Title,
    q.CreationDate,
    q.Score,
    q.Reputation,
    q.OwnerDisplayName,
    q.OwnerUserId,
    q.LastActivityDate,
    q.CommentCount,
    q.AnswerCount,
    (SELECT COUNT(*) FROM Posts AS a
     WHERE a.ParentId = q.PostId AND a.PostTypeId = 2) AS ChildAnswerCount,
    (SELECT AVG(Score) FROM Votes WHERE PostId = q.PostId) AS AvgVoteScore
  FROM ranked_questions q
  WHERE q.rn_in_month = 1
)
SELECT
  cs.PostId,
  cs.Title,
  cs.CreationDate,
  cs.Score,
  cs.Reputation,
  cs.OwnerDisplayName,
  cs.OwnerUserId,
  cs.LastActivityDate,
  cs.CommentCount,
  cs.AnswerCount,
  csc.ChildAnswerCount,
  csc.AvgVoteScore,
  rt.Name AS LastEditorRole,
  pa.tag_post_count,
  pa.score_sum,
  pa.avg_views,
  ARRAY_AGG(DISTINCT rbd.RelatedPostId) FILTER (WHERE rbd.RelatedPostId IS NOT NULL) AS RelatedPosts
FROM correlated_subselect cs
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    pg.UserId,
    pg.Name AS LastEditorRole
  FROM (
    SELECT DISTINCT On (p.Id) p.Id, v.UserId, u.DisplayName
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    JOIN Users u ON v.UserId = u.Id
  ) pg
) rt ON rt.PostId = cs.PostId
LEFT JOIN recent_activity ra ON ra.PostId = cs.PostId
LEFT JOIN (
  SELECT
    t.TagName,
    COUNT(*) AS tag_post_count,
    SUM(p.Score) AS score_sum,
    AVG(p.ViewCount) AS avg_views
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
  ) t
  WHERE p.PostTypeId = 1
  GROUP BY t.TagName
) pa ON TRUE
LEFT JOIN (
  SELECT PostId, RelatedPostId
  FROM PostLinks
  WHERE LinkTypeId = 1
) rbd ON rbd.PostId = cs.PostId
GROUP BY
  cs.PostId, cs.Title, cs.CreationDate, cs.Score, cs.Reputation,
  cs.OwnerDisplayName, cs.OwnerUserId, cs.LastActivityDate, cs.CommentCount,
  cs.AnswerCount, csc.ChildAnswerCount, csc.AvgVoteScore, rt.LastEditorRole,
  pa.tag_post_count, pa.score_sum, pa.avg_views
ORDER BY cs.LastActivityDate DESC
LIMIT 100;