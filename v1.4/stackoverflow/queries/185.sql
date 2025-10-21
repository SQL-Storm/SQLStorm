-- {"query": "185.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1680} 
WITH
recent_questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
         u.DisplayName, u.Reputation
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '180 days'
),
tags_expanded AS (
  SELECT rq.Id, rq.Title, rq.CreationDate, rq.OwnerUserId, rq.Score, rq.ViewCount,
         rq.Tags, rq.DisplayName, rq.Reputation,
         t.tag
  FROM recent_questions rq
  CROSS JOIN LATERAL UNNEST(string_to_array(substr(rq.Tags, 2, length(rq.Tags) - 2), '><')) AS t(tag)
),
tag_stats AS (
  SELECT tag,
         COUNT(*) AS nq,
         AVG(Score) AS avg_score,
         MAX(Score) AS max_score
  FROM tags_expanded
  GROUP BY tag
),
top_posts AS (
  SELECT te.*, ROW_NUMBER() OVER (PARTITION BY te.tag ORDER BY te.Score DESC, te.CreationDate DESC) AS rn
  FROM tags_expanded te
)
SELECT tp.Id,
       tp.Title,
       tp.CreationDate,
       tp.OwnerUserId,
       tp.DisplayName,
       tp.Reputation,
       tp.Score,
       tp.ViewCount,
       tp.Tags,
       tp.tag,
       ts.nq AS tag_post_count,
       ROW_NUMBER() OVER (PARTITION BY tp.OwnerUserId ORDER BY tp.CreationDate DESC) AS user_recent_rank
FROM top_posts tp
LEFT JOIN tag_stats ts ON tp.tag = ts.tag
WHERE tp.rn = 1
ORDER BY tp.Reputation DESC NULLS LAST, tp.Score DESC
LIMIT 200;