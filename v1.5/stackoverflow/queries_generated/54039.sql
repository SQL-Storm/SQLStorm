-- {"query": "54039.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1102} 

WITH tag_posts AS (
    SELECT p.Id,
           p.Score,
           p.OwnerUserId,
           t.Id   AS TagId
    FROM   Posts p
    JOIN   LATERAL regexp_split_to_table(p.Tags, '<>|>') AS tg(tag)
           ON tg.tag <> ''
    JOIN   Tags t
           ON t.TagName = tg.tag
    WHERE  p.PostTypeId = 1
),
vote_stats AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS favorites
    FROM   Votes v
    GROUP  BY v.PostId
)
SELECT t.TagName,
       COUNT(p.Id)                 AS question_count,
       AVG(p.Score)                AS average_score,
       COALESCE(SUM(vs.upvotes), 0)      AS total_upvotes,
       COALESCE(SUM(vs.downvotes), 0)    AS total_downvotes,
       COALESCE(SUM(vs.favorites), 0)    AS total_favorites,
       COUNT(DISTINCT p.OwnerUserId) AS contributor_count
FROM   tag_posts p
JOIN   Tags t
       ON t.Id = p.TagId
LEFT JOIN vote_stats vs
       ON vs.PostId = p.Id
GROUP  BY t.TagName
ORDER  BY average_score DESC, question_count DESC
LIMIT  5;
