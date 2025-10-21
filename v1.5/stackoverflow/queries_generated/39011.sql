-- {"query": "39011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2669} 

WITH
  post_tags AS (
    SELECT
      p.Id AS post_id,
      unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
  ),
  tag_performance AS (
    SELECT
      pt.tag,
      COUNT(*)               AS question_count,
      AVG(p.Score)           AS avg_score,
      MAX(p.ViewCount)       AS max_views
    FROM post_tags pt
    JOIN Posts p
      ON p.Id = pt.post_id
    GROUP BY pt.tag
  ),
  user_scores AS (
    SELECT
      u.Id                          AS user_id,
      u.DisplayName,
      u.Reputation,
      ROW_NUMBER() OVER (
        PARTITION BY u.Location
        ORDER BY u.Reputation DESC
      )                             AS loc_rank,
      COUNT(*) FILTER (WHERE b.Class = 1) AS gold_badges,
      COUNT(*) FILTER (WHERE b.Class = 2) AS silver_badges,
      COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_badges
    FROM Users u
    LEFT JOIN Badges b
      ON b.UserId = u.Id
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.Location
  ),
  vote_stats AS (
    SELECT
      p.OwnerUserId                AS user_id,
      COUNT(v.Id)                  AS total_votes,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
    FROM Votes v
    JOIN Posts p
      ON p.Id = v.PostId
    GROUP BY p.OwnerUserId
  )
SELECT
  tp.tag,
  tp.question_count,
  tp.avg_score,
  tp.max_views,
  us.DisplayName,
  us.Reputation,
  us.loc_rank,
  us.gold_badges,
  us.silver_badges,
  us.bronze_badges,
  COALESCE(vs.total_votes, 0) AS total_votes,
  COALESCE(vs.up_votes,    0) AS up_votes,
  COALESCE(vs.down_votes,  0) AS down_votes
FROM tag_performance tp
CROSS JOIN LATERAL (
  SELECT
    us.*
  FROM user_scores us
  JOIN post_tags pt
    ON pt.tag = tp.tag
  JOIN Posts p
    ON p.Id = pt.post_id
   AND p.OwnerUserId = us.user_id
  ORDER BY p.ViewCount DESC
  LIMIT 1
) us
LEFT JOIN vote_stats vs
  ON vs.user_id = us.user_id
ORDER BY
  tp.question_count DESC,
  vs.up_votes DESC
LIMIT 50;
