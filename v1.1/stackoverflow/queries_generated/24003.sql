-- {"query": "24003.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3061} 
WITH
    post_votes AS (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
            MAX(CASE WHEN VoteTypeId = 1 THEN 1 ELSE 0 END) AS accepted
        FROM Votes
        GROUP BY PostId
    ),
    post_scores AS (
        SELECT
            p.Id          AS PostId,
            p.OwnerUserId,
            p.PostTypeId,
            p.Score,
            COALESCE(string_to_array(p.Tags,'><'), ARRAY[]::varchar[]) AS TagArray,
            v.upvotes,
            v.downvotes,
            v.accepted
        FROM Posts p
        LEFT JOIN post_votes v ON v.PostId = p.Id
    ),
    user_totals AS (
        SELECT
            u.Id           AS UserId,
            u.DisplayName,
            u.Reputation,
            SUM(CASE WHEN ps.PostTypeId = 2 THEN ps.Score ELSE 0 END) AS answer_score,
            COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END)            AS answers,
            COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END)            AS questions,
            SUM(CASE WHEN ps.upvotes IS NULL THEN 0 ELSE ps.upvotes END) AS total_upvotes
        FROM Users u
        LEFT JOIN post_scores ps ON ps.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    combined AS (
        SELECT UserId, answer_score AS total_score
        FROM user_totals
        WHERE answers > 0
        UNION ALL
        SELECT UserId, questions * 10 AS total_score
        FROM user_totals
        WHERE questions > 0
    ),
    ranked AS (
        SELECT
            UserId,
            total_score,
            ROW_NUMBER() OVER (ORDER BY total_score DESC) AS rnk
        FROM combined
    )
SELECT
    r.UserId,
    u.DisplayName,
    u.Reputation,
    r.total_score,
    r.rnk,
    (SELECT string_agg(tag, ', ') FROM (
        SELECT UNNEST(ps.TagArray) AS tag
        FROM post_scores ps
        WHERE ps.OwnerUserId = r.UserId
          AND ps.PostTypeId = 1
        GROUP BY tag
        ORDER BY COUNT(*) DESC
        LIMIT 3
    ) t) AS top_tags,
    CASE WHEN r.answers = 0 THEN NULL
         ELSE 100.0 * (
             SELECT COUNT(*) FROM Posts p
             WHERE p.OwnerUserId = r.UserId
               AND p.PostTypeId = 2
               AND p.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
         ) / r.answers
    END AS accepted_pct
FROM ranked r
JOIN Users u ON u.Id = r.UserId
WHERE r.rnk <= 20
ORDER BY r.rnk;