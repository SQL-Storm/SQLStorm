-- {"query": "3634.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2480}
WITH
    user_posts AS (
        SELECT
            p.OwnerUserId                     AS user_id,
            p.Id                              AS post_id,
            p.PostTypeId,
            p.Score,
            p.CreationDate,
            COALESCE(p.ViewCount, 0)          AS view_cnt,
            CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS has_accepted,
            (SELECT COUNT(*) FROM Votes   v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS up_votes,
            (SELECT COUNT(*) FROM Votes   v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS down_votes,
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)                     AS comment_cnt
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
    ),

    user_agg AS (
        SELECT
            up.user_id,
            COUNT(*)                                      AS total_posts,
            SUM(CASE WHEN up.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
            SUM(CASE WHEN up.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
            SUM(up.Score)                                 AS total_score,
            CAST(AVG(up.Score) AS DECIMAL(10,2))          AS avg_score,
            SUM(up.has_accepted)                          AS accepted_answers,
            SUM(up.view_cnt)                              AS total_views,
            SUM(up.up_votes)                              AS total_up_votes,
            SUM(up.down_votes)                            AS total_down_votes,
            SUM(up.comment_cnt)                           AS total_comments,
            MAX(up.CreationDate)                          AS last_post_date
        FROM user_posts up
        GROUP BY up.user_id
    ),

    user_badges AS (
        SELECT
            b.UserId,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_badges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_badges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_badges,
            COUNT(*)                            AS total_badges
        FROM Badges b
        GROUP BY b.UserId
    ),

    user_tag_stats AS (
        SELECT
            p.OwnerUserId                              AS user_id,
            t.TagName,
            COUNT(*)                                   AS tag_post_cnt,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                               ORDER BY COUNT(*) DESC) AS tag_rank
        FROM Posts p
        JOIN LATERAL unnest(string_to_array(trim(both '><' FROM p.Tags), '><')) AS tag(tag_name) ON TRUE
        JOIN Tags t ON t.TagName = tag.tag_name
        WHERE p.OwnerUserId IS NOT NULL
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, t.TagName
    ),

    top_tag_per_user AS (
        SELECT
            uts.user_id,
            uts.TagName,
            uts.tag_post_cnt
        FROM user_tag_stats uts
        WHERE uts.tag_rank = 1
    ),

    combined AS (
        SELECT
            u.Id                                   AS user_id,
            u.DisplayName,
            ua.total_posts,
            ua.questions,
            ua.answers,
            ua.total_score,
            ua.avg_score,
            ua.accepted_answers,
            ua.total_views,
            ua.total_up_votes,
            ua.total_down_votes,
            ua.total_comments,
            ub.gold_badges,
            ub.silver_badges,
            ub.bronze_badges,
            ub.total_badges,
            tp.TagName                            AS top_tag,
            tp.tag_post_cnt                       AS top_tag_post_cnt,
            ROW_NUMBER() OVER (ORDER BY ua.total_score DESC NULLS LAST) AS score_rank,
            CASE
                WHEN u.Reputation > 20000 AND COALESCE(ub.gold_badges,0) > 5 THEN 'Elite'
                WHEN u.Reputation BETWEEN 10000 AND 20000                THEN 'Veteran'
                ELSE 'Member'
            END                                   AS tier,
            COALESCE(u.Location, 'Unknown')       AS location
        FROM Users u
        LEFT JOIN user_agg      ua ON ua.user_id = u.Id
        LEFT JOIN user_badges   ub ON ub.UserId = u.Id
        LEFT JOIN top_tag_per_user tp ON tp.user_id = u.Id
        WHERE (ua.total_posts IS NOT NULL AND ua.total_posts >= 10)
           OR (ub.total_badges IS NOT NULL AND ub.total_badges >= 20)
    )

SELECT *
FROM combined
WHERE tier <> 'Member'

UNION ALL

SELECT
    user_id,
    DisplayName,
    total_posts,
    questions,
    answers,
    total_score,
    avg_score,
    accepted_answers,
    total_views,
    total_up_votes,
    total_down_votes,
    total_comments,
    gold_badges,
    silver_badges,
    bronze_badges,
    total_badges,
    NULL AS top_tag,
    NULL AS top_tag_post_cnt,
    NULL AS score_rank,
    'Rising' AS tier,
    location
FROM combined
WHERE tier = 'Member' AND COALESCE(total_score,0) > 5000

ORDER BY score_rank NULLS LAST, total_score DESC
LIMIT 100;