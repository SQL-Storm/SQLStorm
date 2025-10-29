-- {"query": "5826.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 754} 
WITH recent_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '180 days'
),
tag_stats AS (
  SELECT
    unnest(string_to_array(p.Tags, '> <')) AS tag,
    COUNT(*) AS total_posts,
    AVG(p.Score) AS avg_score,
    SUM(p.ViewCount) AS total_views
  FROM Posts p
  WHERE p.PostTypeId = 1
  GROUP BY tag
),
top_authors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(r.PostId) AS recent_questions
  FROM Users u
  JOIN recent_questions r ON r.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(r.PostId) > 5
),
complex_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    EXISTS (
      SELECT 1
      FROM Votes v
      WHERE v.PostId = p.Id
        AND v.VoteTypeId = 2
        AND v.CreationDate > p.CreationDate
    ) AS had_upmod_after_creation,
    EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = p.Id
        AND pl.RelatedPostId = p.Id -- dummy predicate to exercise correlation
    ) AS has_self_link
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.LastActivityDate > p.CreationDate
),
outer_join_demo AS (
  SELECT
    a.UserId,
    a.DisplayName,
    b.total_posts AS user_total_questions,
    c.total_views AS user_total_views
  FROM top_authors a
  LEFT JOIN (SELECT OwnerUserId, COUNT(*) AS total_posts
             FROM Posts
             WHERE PostTypeId = 1
             GROUP BY OwnerUserId) b ON a.UserId = b.OwnerUserId
  LEFT JOIN (SELECT OwnerUserId, SUM(ViewCount) AS total_views
             FROM Posts
             WHERE PostTypeId = 1
             GROUP BY OwnerUserId) c ON a.UserId = c.OwnerUserId
)
SELECT
  ra.UserId,
  ra.DisplayName,
  ra.Reputation,
  ra.user_total_questions,
  ra.user_total_views,
  tt.tag,
  tt.total_posts AS tag_post_count,
  tt.avg_score AS tag_avg_score,
  tt.total_views AS tag_total_views,
  coalesce(c.complex_count, 0) AS complex_post_count
FROM outer_join_demo ra
JOIN top_authors ta ON ra.UserId = ta.UserId
LEFT JOIN tag_stats tt ON TRUE
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    COUNT(*) AS complex_count
  FROM complex_posts p
  GROUP BY p.OwnerUserId
) c ON ra.UserId = c.OwnerUserId
ORDER BY ra.Reputation DESC NULLS LAST, ra.user_total_questions DESC NULLS LAST
LIMIT 100;