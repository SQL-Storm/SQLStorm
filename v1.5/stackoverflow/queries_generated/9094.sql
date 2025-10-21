-- {"query": "9094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 4094} 

WITH user_stats AS (
  SELECT
    u.Id                          AS user_id,
    u.DisplayName,
    COUNT(DISTINCT p.Id)          AS question_count,
    COUNT(DISTINCT p2.Id)         AS answer_count,
    SUM(
      CASE WHEN v.VoteTypeId = 2 THEN  1
           WHEN v.VoteTypeId = 3 THEN -1
           ELSE 0
      END
    )                              AS vote_balance,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rep_rank
  FROM Users u
  LEFT JOIN Posts p   ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
  LEFT JOIN Posts p2  ON p2.OwnerUserId = u.Id AND p2.PostTypeId = 2
  LEFT JOIN Votes v   ON v.UserId      = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_stats AS (
  SELECT
    p.Id                            AS post_id,
    p.OwnerUserId,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    COUNT(c.Id) OVER (PARTITION BY p.Id) AS comment_count,
    SUM(
      CASE WHEN v2.VoteTypeId = 2 THEN  1
           WHEN v2.VoteTypeId = 3 THEN -1
           ELSE 0
      END
    ) OVER (PARTITION BY p.Id)       AS vote_score,
    RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS type_score_rank
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id
  LEFT JOIN Votes v2   ON v2.PostId = p.Id
),
duplicate_info AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS duplicate_count,
    MAX(pl.CreationDate)                   AS last_dup_date
  FROM PostLinks pl
  GROUP BY pl.PostId
),
combined AS (
  SELECT
    ps.*,
    us.DisplayName,
    us.vote_balance,
    di.duplicate_count,
    di.last_dup_date
  FROM post_stats ps
  LEFT JOIN user_stats us ON us.user_id = ps.OwnerUserId
  LEFT JOIN duplicate_info di ON di.PostId = ps.post_id
  WHERE ps.CreationDate > NOW() - INTERVAL '1 year'
),
tagged_posts AS (
  SELECT
    p.Id,
    unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tag_activity AS (
  SELECT
    tp.tag,
    COUNT(DISTINCT tp.Id) AS question_cnt,
    COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN tp.Id END) AS accepted_cnt,
    SUM(ps.Score)         AS total_score
  FROM tagged_posts tp
  JOIN Posts p       ON p.Id = tp.Id
  JOIN post_stats ps ON ps.post_id = p.Id
  GROUP BY tp.tag
)
SELECT
  c.post_id,
  c.DisplayName,
  c.Score,
  c.vote_score,
  c.comment_count,
  COALESCE(c.duplicate_count,0) AS duplicate_count,
  CASE
    WHEN c.duplicate_count IS NULL THEN 'No dups'
    ELSE CONCAT(c.duplicate_count,' dups')
  END AS dup_label,
  ta.tag,
  ta.question_cnt,
  ta.accepted_cnt,
  ta.total_score,
  (SELECT AVG(score) FROM Posts WHERE OwnerUserId = c.OwnerUserId)                             AS avg_user_score,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.post_id AND v.CreationDate > c.CreationDate) AS votes_after,
  COALESCE(us.question_count,0) + COALESCE(us.answer_count,0)                                  AS total_posts_by_user
FROM combined c
FULL OUTER JOIN user_stats us   ON us.user_id = c.OwnerUserId
INNER JOIN tag_activity ta      ON ta.tag LIKE CASE WHEN c.Score % 2 = 0 THEN ta.tag ELSE '%' END
WHERE
  (c.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) OR c.comment_count > 5)
  AND (c.vote_score BETWEEN -5 AND 20 OR c.duplicate_count IS NOT NULL)
ORDER BY c.Score DESC
LIMIT 100

UNION

SELECT
  NULL,
  '--------',
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL

INTERSECT

SELECT
  c.post_id,
  c.DisplayName,
  c.Score,
  c.vote_score,
  c.comment_count,
  c.duplicate_count,
  CASE
    WHEN c.duplicate_count IS NULL THEN 'No dups'
    ELSE CONCAT(c.duplicate_count,' dups')
  END,
  ta.tag,
  ta.question_cnt,
  ta.accepted_cnt,
  ta.total_score,
  (SELECT AVG(score) FROM Posts WHERE OwnerUserId = c.OwnerUserId),
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = c.post_id AND v.CreationDate > c.CreationDate),
  COALESCE(us.question_count,0) + COALESCE(us.answer_count,0)
FROM combined c
JOIN tag_activity ta    ON ta.tag = 'sql'
JOIN user_stats us      ON us.user_id = c.OwnerUserId
WHERE c.vote_score > 10
ORDER BY c.post_id
LIMIT 10;
