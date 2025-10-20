-- {"query": "54094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2042} 

WITH post_tags AS (
    SELECT 
        p.Id            AS post_id,
        p.PostTypeId    AS post_type,
        p.OwnerUserId   AS owner_user,
        UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '>')) AS tag
    FROM Posts p
    WHERE p.Tags IS NOT NULL
),
tag_vote_agg AS (
    SELECT 
        pt.tag,
        COUNT(DISTINCT pt.post_id)                     AS total_posts,
        SUM(upvote_cnt)                                AS total_upvotes,
        SUM(downvote_cnt)                              AS total_downvotes,
        SUM(offense_cnt)                               AS total_offensive,
        AVG(p.Score)                                   AS avg_post_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score)    AS median_post_score,
        MIN(u.Reputation)                              AS min_rep,
        MAX(u.Reputation)                              AS max_rep,
        COUNT(DISTINCT pt.owner_user)                  AS unique_user_count
    FROM post_tags pt
    JOIN Posts p ON p.Id = pt.post_id
    LEFT JOIN LATERAL (
        SELECT
            SUM(CASE WHEN v.VoteTypeId=2 THEN 1 ELSE 0 END) AS upvote_cnt,
            SUM(CASE WHEN v.VoteTypeId=3 THEN 1 ELSE 0 END) AS downvote_cnt,
            SUM(CASE WHEN v.VoteTypeId=4 THEN 1 ELSE 0 END) AS offense_cnt
        FROM Votes v
        WHERE v.PostId = pt.post_id
    ) vc ON TRUE
    LEFT JOIN Users u ON u.Id = pt.owner_user
    GROUP BY pt.tag
),
tag_user_rank AS (
    SELECT
        pt.tag,
        pt.owner_user,
        RANK() OVER (PARTITION BY pt.tag ORDER BY u.Reputation DESC) AS user_rank
    FROM post_tags pt
    JOIN Users u ON u.Id = pt.owner_user
)
SELECT
    s.tag,
    s.total_posts,
    s.total_upvotes,
    s.total_downvotes,
    s.total_offensive,
    s.avg_post_score,
    s.median_post_score,
    s.min_rep,
    s.max_rep,
    s.unique_user_count
FROM tag_vote_agg s
ORDER BY s.total_upvotes DESC
LIMIT 20;
