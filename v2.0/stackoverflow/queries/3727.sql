-- {"query": "3727.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2258}
WITH 
user_badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*)                                   AS total_badges,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END)    AS gold_badges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END)    AS silver_badges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END)    AS bronze_badges,
        COUNT(CASE WHEN b.TagBased = TRUE THEN 1 END) AS tag_based_badges,
        STRING_AGG(DISTINCT b.Name, ', ')          AS badge_names
    FROM Badges b
    GROUP BY b.UserId
),
user_post_stats AS (
    SELECT 
        p.OwnerUserId                                   AS user_id,
        COUNT(*)                                        AS total_posts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)    AS questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)    AS answers,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END)    AS question_score_sum,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END)    AS answer_score_sum,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END)      AS avg_question_views,
        MAX(p.CreationDate)                             AS last_post_date,
        MIN(p.CreationDate)                             AS first_post_date,
        CASE 
            WHEN COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) = 0 THEN NULL
            ELSE 
                ROUND(
                    100.0 * 
                    COUNT(CASE WHEN p.PostTypeId = 2 AND p.Id = p.AcceptedAnswerId THEN 1 END)
                    / NULLIF(COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END), 0), 2)
        END                                           AS acceptance_rate_pct
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
user_recent_votes AS (
    SELECT 
        u.Id                                 AS user_id,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.CreationDate >= DATE '2024-10-01' - INTERVAL '30' DAY)          AS votes_last_30d,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 2 
           AND v.CreationDate >= DATE '2024-10-01' - INTERVAL '30' DAY)          AS upvotes_last_30d,
        (SELECT COUNT(*) 
         FROM Votes v 
         WHERE v.UserId = u.Id 
           AND v.VoteTypeId = 3 
           AND v.CreationDate >= DATE '2024-10-01' - INTERVAL '30' DAY)          AS downvotes_last_30d
    FROM Users u
),
question_tags AS (
    SELECT 
        p.Id                                 AS question_id,
        UNNEST(
            CASE 
                WHEN p.Tags IS NULL THEN ARRAY[]::text[] -- keep for dialects that support array literals
                ELSE string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')
            END
        )                                    AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
user_top_tags AS (
    SELECT 
        p.OwnerUserId                                   AS user_id,
        t.tag,
        COUNT(*)                                        AS tag_uses,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId 
                           ORDER BY COUNT(*) DESC)   AS tag_rank
    FROM Posts p
    JOIN question_tags t ON p.Id = t.question_id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.tag
),
user_combined AS (
    SELECT 
        u.Id                                         AS user_id,
        u.DisplayName,
        COALESCE(u.Reputation, 0)                    AS reputation,
        COALESCE(bs.total_badges, 0)                 AS total_badges,
        COALESCE(bs.gold_badges, 0)                  AS gold_badges,
        COALESCE(bs.silver_badges, 0)                AS silver_badges,
        COALESCE(bs.bronze_badges, 0)                AS bronze_badges,
        COALESCE(bs.tag_based_badges, 0)             AS tag_based_badges,
        COALESCE(bs.badge_names, '')                 AS badge_names,
        COALESCE(ps.total_posts, 0)                  AS total_posts,
        COALESCE(ps.questions, 0)                    AS question_count,
        COALESCE(ps.answers, 0)                      AS answer_count,
        COALESCE(ps.question_score_sum, 0)           AS question_score_sum,
        COALESCE(ps.answer_score_sum, 0)             AS answer_score_sum,
        COALESCE(ps.avg_question_views, 0)           AS avg_question_views,
        COALESCE(ps.acceptance_rate_pct, NULL)       AS acceptance_rate_pct,
        rv.votes_last_30d,
        rv.upvotes_last_30d,
        rv.downvotes_last_30d,
        ROUND(
            (COALESCE(u.Reputation,0)/1000.0) * 
            (COALESCE(ps.total_posts,0) + COALESCE(rv.votes_last_30d,0)) *
            (1 + COALESCE(ps.acceptance_rate_pct,0)/100.0)
        , 2)                                          AS activity_score
    FROM Users u
    FULL OUTER JOIN user_badge_stats bs   ON u.Id = bs.UserId
    FULL OUTER JOIN user_post_stats ps    ON u.Id = ps.user_id
    FULL OUTER JOIN user_recent_votes rv ON u.Id = rv.user_id
),
final_result AS (
    SELECT 
        uc.user_id,
        uc.DisplayName,
        uc.reputation,
        uc.total_badges,
        uc.gold_badges,
        uc.silver_badges,
        uc.bronze_badges,
        uc.tag_based_badges,
        uc.badge_names,
        uc.total_posts,
        uc.question_count,
        uc.answer_count,
        uc.question_score_sum,
        uc.answer_score_sum,
        uc.avg_question_views,
        uc.acceptance_rate_pct,
        uc.votes_last_30d,
        uc.upvotes_last_30d,
        uc.downvotes_last_30d,
        uc.activity_score,
        tt.tag   AS top_tag,
        tt.tag_uses,
        tt.tag_rank
    FROM user_combined uc
    LEFT JOIN LATERAL (
        SELECT tag, tag_uses, tag_rank
        FROM user_top_tags utt
        WHERE utt.user_id = uc.user_id
          AND utt.tag_rank = 1
    ) tt ON TRUE
    WHERE uc.user_id IS NOT NULL

    UNION ALL

    SELECT 
        NULL AS user_id,
        'Site Summary' AS DisplayName,
        SUM(reputation)               AS reputation,
        SUM(total_badges)              AS total_badges,
        SUM(gold_badges)               AS gold_badges,
        SUM(silver_badges)             AS silver_badges,
        SUM(bronze_badges)             AS bronze_badges,
        SUM(tag_based_badges)          AS tag_based_badges,
        NULL                           AS badge_names,
        SUM(total_posts)               AS total_posts,
        SUM(question_count)            AS question_count,
        SUM(answer_count)              AS answer_count,
        SUM(question_score_sum)        AS question_score_sum,
        SUM(answer_score_sum)          AS answer_score_sum,
        AVG(avg_question_views)        AS avg_question_views,
        NULL                           AS acceptance_rate_pct,
        SUM(votes_last_30d)            AS votes_last_30d,
        SUM(upvotes_last_30d)          AS upvotes_last_30d,
        SUM(downvotes_last_30d)        AS downvotes_last_30d,
        ROUND(AVG(activity_score),2)   AS activity_score,
        NULL                           AS top_tag,
        NULL                           AS tag_uses,
        NULL                           AS tag_rank
    FROM user_combined
)
SELECT *
FROM final_result
ORDER BY 
    CASE WHEN user_id IS NULL THEN 0 ELSE 1 END,
    activity_score DESC NULLS LAST;