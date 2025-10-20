-- {"query": "55011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1379} 

WITH
    -- Expand question tags into one row per tag
    expanded_tags AS (
        SELECT
            p.Id                AS post_id,
            p.OwnerUserId       AS user_id,
            p.Score             AS post_score,
            p.CreationDate      AS post_date,
            t.TagName
        FROM Posts p
        CROSS JOIN LATERAL
            regexp_split_to_table(
                substring(p.Tags FROM 2 FOR length(p.Tags)-2),
                '><'
            ) AS tag_name
        JOIN Tags t ON t.TagName = tag_name
        WHERE p.PostTypeId = 1                  -- only questions
    ),

    -- Aggregate per user overall activity
    user_overview AS (
        SELECT
            user_id,
            COUNT(*)                         AS total_questions,
            SUM(post_score)                  AS total_score,
            MAX(post_date)                   AS last_question_date
        FROM expanded_tags
        GROUP BY user_id
    ),

    -- Badge counts per user (gold, silver, bronze)
    badge_counts AS (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
        FROM Badges
        GROUP BY UserId
    ),

    -- Vote aggregates per post
    vote_agg AS (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes
        GROUP BY PostId
    ),

    -- Vote aggregates per user (sum across their questions)
    user_votes AS (
        SELECT
            e.user_id,
            SUM(v.up_votes)   AS total_up_votes,
            SUM(v.down_votes) AS total_down_votes
        FROM expanded_tags e
        JOIN vote_agg v ON v.PostId = e.post_id
        GROUP BY e.user_id
    ),

    -- Tag‑specific user statistics
    tag_user_stats AS (
        SELECT
            TagName,
            user_id,
            COUNT(*)                         AS questions_in_tag,
            SUM(post_score)                  AS tag_score,
            ROW_NUMBER() OVER (
                PARTITION BY TagName
                ORDER BY SUM(post_score) DESC, COUNT(*) DESC
            )                                 AS tag_rank
        FROM expanded_tags
        GROUP BY TagName, user_id
    )

SELECT
    tu.TagName,
    u.DisplayName,
    tu.questions_in_tag,
    tu.tag_score,
    tu.tag_rank,
    uo.total_questions,
    uo.total_score,
    uo.last_question_date,
    bc.gold,
    bc.silver,
    bc.bronze,
    uv.total_up_votes,
    uv.total_down_votes
FROM tag_user_stats tu
JOIN Users u                ON u.Id = tu.user_id
LEFT JOIN user_overview uo  ON uo.user_id = tu.user_id
LEFT JOIN badge_counts bc   ON bc.UserId = tu.user_id
LEFT JOIN user_votes uv     ON uv.user_id = tu.user_id
ORDER BY tu.TagName, tu.tag_rank
LIMIT 1000;
