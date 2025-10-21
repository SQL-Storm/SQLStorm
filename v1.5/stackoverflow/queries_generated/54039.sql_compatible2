WITH tag_posts AS (
    SELECT p.Id,
           p.Score,
           p.OwnerUserId,
           t.Id   AS TagId
    FROM   Posts p
    JOIN   LATERAL (
            SELECT regexp_split_to_table(p.Tags, '<>|>') AS tag
        ) AS sub
           ON sub.tag <> ''
    JOIN   Tags t
           ON t.TagName = sub.tag
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