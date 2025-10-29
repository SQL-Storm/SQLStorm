-- {"query": "3591.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2103} 

/*  Benchmarking query – combines CTEs, window functions, outer joins, 
    correlated subqueries, set operators, complex predicates, string ops, 
    and NULL logic. */
WITH RECURSIVE tag_hierarchy AS (
    SELECT t.Id, t.TagName, NULL::int AS ParentTagId, 1 AS lvl
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT t.Id, t.TagName, th.Id, th.lvl + 1
    FROM Tags t
    JOIN tag_hierarchy th ON t.TagName LIKE th.TagName || '-%'
),
user_agg AS (
    SELECT 
        u.Id                               AS user_id,
        COALESCE(u.DisplayName, 'Anonymous') AS display_name,
        u.Reputation,
        COUNT(DISTINCT p.Id)               AS total_posts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS questions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS answers,
        COUNT(DISTINCT b.Id)               AS badges_earned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        COALESCE(SUM(v_up.VoteTypeId = 2)::int,0)   AS upvotes_given,
        COALESCE(SUM(v_down.VoteTypeId = 3)::int,0) AS downvotes_given,
        MAX(p.CreationDate)               AS last_post_date,
        MAX(v_creation.CreationDate)       AS last_vote_date,
        CONCAT('U_', u.Id)                 AS user_key
    FROM Users u
    LEFT JOIN Posts p          ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b         ON b.UserId = u.Id
    LEFT JOIN Votes v_up       ON v_up.UserId = u.Id AND v_up.VoteTypeId = 2
    LEFT JOIN Votes v_down     ON v_down.UserId = u.Id AND v_down.VoteTypeId = 3
    LEFT JOIN Votes v_creation ON v_creation.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
post_quality AS (
    SELECT 
        p.Id                              AS post_id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(NULLIF(p.Score,0),1) / NULLIF(p.ViewCount,0) AS score_per_view,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND EXISTS (
                    SELECT 1 FROM Votes v 
                    WHERE v.PostId = p.Id AND v.VoteTypeId = 1
                ) THEN 1
            ELSE 0
        END                               AS is_accepted_or_favored,
        ARRAY_TO_STRING(ARRAY[
            CASE WHEN p.Tags LIKE '%<java>%'
                 THEN 'Java' ELSE NULL END,
            CASE WHEN p.Tags LIKE '%<sql>%'
                 THEN 'SQL' ELSE NULL END,
            CASE WHEN p.Tags LIKE '%<c#>%'
                 THEN 'C#' ELSE NULL END
        ], ',')                           AS detected_tags
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)               -- questions & answers only
),
user_activity AS (
    SELECT 
        ua.user_id,
        ua.display_name,
        ua.reputation,
        ua.total_posts,
        ua.questions,
        ua.answers,
        ua.badges_earned,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.upvotes_given,
        ua.downvotes_given,
        ua.last_post_date,
        ua.last_vote_date,
        ua.user_key,
        ROW_NUMBER() OVER (PARTITION BY ua.user_id ORDER BY ua.reputation DESC) AS rep_rank,
        RANK() OVER (ORDER BY (ua.upvotes_given - ua.downvotes_given) DESC) AS net_vote_rank,
        PERCENT_RANK() OVER (ORDER BY ua.total_posts DESC) AS post_percentile,
        NTILE(4) OVER (ORDER BY ua.reputation) AS reputation_quartile
    FROM user_agg ua
),
post_enhanced AS (
    SELECT 
        pq.post_id,
        pq.PostTypeId,
        pq.Score,
        pq.ViewCount,
        pq.AnswerCount,
        pq.FavoriteCount,
        pq.score_per_view,
        pq.is_accepted_or_favored,
        pq.detected_tags,
        COALESCE(lc.LinkCount,0) AS linked_posts,
        COALESCE(dup.DuplicateCount,0) AS duplicate_posts,
        CASE 
            WHEN pq.Score > 100 THEN 'Hot'
            WHEN pq.ViewCount > 1000 THEN 'Popular'
            ELSE 'Regular'
        END AS popularity_tier
    FROM post_quality pq
    LEFT JOIN (
        SELECT pl.PostId, COUNT(*) AS LinkCount
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 1
        GROUP BY pl.PostId
    ) lc ON lc.PostId = pq.post_id
    LEFT JOIN (
        SELECT pl.PostId, COUNT(*) AS DuplicateCount
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3
        GROUP BY pl.PostId
    ) dup ON dup.PostId = pq.post_id
),
final_report AS (
    SELECT 
        ua.user_key,
        ua.display_name,
        ua.reputation,
        ua.rep_rank,
        ua.net_vote_rank,
        ua.post_percentile,
        ua.reputation_quartile,
        ua.total_posts,
        ua.questions,
        ua.answers,
        ua.badges_earned,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.upvotes_given,
        ua.downvotes_given,
        DATE_TRUNC('day', ua.last_post_date)::date AS last_post_day,
        DATE_TRUNC('day', ua.last_vote_date)::date AS last_vote_day,
        COALESCE(pe.popularity_tier, 'N/A') AS top_post_popularity,
        COALESCE(pe.detected_tags, '') AS top_post_tags
    FROM user_activity ua
    LEFT JOIN post_enhanced pe
        ON pe.post_id = (
            SELECT p.Id
            FROM Posts p
            WHERE p.OwnerUserId = ua.user_id
              AND p.PostTypeId = 1          -- only questions
            ORDER BY p.Score DESC NULLS LAST
            LIMIT 1
        )
)
SELECT *
FROM final_report
WHERE reputation_quartile = 4          -- top‑quartile users only
   OR total_posts > 100
UNION ALL
SELECT
    'TOTAL'                 AS user_key,
    'Site Summary'          AS display_name,
    SUM(reputation)         AS reputation,
    NULL                    AS rep_rank,
    NULL                    AS net_vote_rank,
    NULL                    AS post_percentile,
    NULL                    AS reputation_quartile,
    SUM(total_posts)        AS total_posts,
    SUM(questions)          AS questions,
    SUM(answers)            AS answers,
    SUM(badges_earned)      AS badges_earned,
    SUM(gold_badges)        AS gold_badges,
    SUM(silver_badges)      AS silver_badges,
    SUM(bronze_badges)      AS bronze_badges,
    SUM(upvotes_given)      AS upvotes_given,
    SUM(downvotes_given)    AS downvotes_given,
    NULL                    AS last_post_day,
    NULL                    AS last_vote_day,
    NULL                    AS top_post_popularity,
    NULL                    AS top_post_tags
FROM final_report
WHERE user_key <> 'TOTAL';
