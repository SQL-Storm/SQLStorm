WITH
    expanded_tags AS (
        SELECT
            p.Id                AS post_id,
            p.OwnerUserId       AS user_id,
            p.Score             AS post_score,
            p.CreationDate      AS post_date,
            t.TagName
        FROM Posts p
        CROSS JOIN LATERAL (
            -- split tags like '<tag1><tag2>' into rows
            -- This implementation uses a recursive CTE to split on '><' after trimming enclosing '<' and '>'
            WITH RECURSIVE parts(part, rest) AS (
                SELECT
                    CASE
                        WHEN TRIM(BOTH FROM TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) = '' THEN NULL
                        ELSE
                            -- initial part is up to first '><' or whole string
                            CASE
                                WHEN POSITION('><' IN TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) = 0
                                THEN TRIM(BOTH FROM TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)))
                                ELSE SUBSTRING(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) FROM 1 FOR POSITION('><' IN TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) - 1)
                            END
                    END,
                    CASE
                        WHEN TRIM(BOTH FROM TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) = '' THEN NULL
                        ELSE
                            CASE
                                WHEN POSITION('><' IN TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) = 0
                                THEN NULL
                                ELSE SUBSTRING(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)) FROM POSITION('><' IN TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags))) + 2)
                            END
                    END
            UNION ALL
                SELECT
                    CASE
                        WHEN rest IS NULL THEN NULL
                        WHEN POSITION('><' IN rest) = 0 THEN rest
                        ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest) - 1)
                    END,
                    CASE
                        WHEN rest IS NULL THEN NULL
                        WHEN POSITION('><' IN rest) = 0 THEN NULL
                        ELSE SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    END
                FROM parts
                WHERE rest IS NOT NULL
            )
            SELECT part AS tag_name
            FROM parts
            WHERE part IS NOT NULL
        ) AS tag_split(tag_name)
        JOIN Tags t ON t.TagName = tag_split.tag_name
        WHERE p.PostTypeId = 1
    ),

    user_overview AS (
        SELECT
            user_id,
            COUNT(*)                         AS total_questions,
            SUM(post_score)                  AS total_score,
            MAX(post_date)                   AS last_question_date
        FROM expanded_tags
        GROUP BY user_id
    ),

    badge_counts AS (
        SELECT
            UserId,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
        FROM Badges
        GROUP BY UserId
    ),

    vote_agg AS (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS up_votes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS down_votes
        FROM Votes
        GROUP BY PostId
    ),

    user_votes AS (
        SELECT
            e.user_id,
            SUM(v.up_votes)   AS total_up_votes,
            SUM(v.down_votes) AS total_down_votes
        FROM expanded_tags e
        JOIN vote_agg v ON v.PostId = e.post_id
        GROUP BY e.user_id
    ),

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