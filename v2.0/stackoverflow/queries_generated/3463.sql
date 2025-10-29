-- {"query": "3463.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2685} 

WITH
    -- 1. Rank all users by reputation
    ranked_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS rn
        FROM Users u
    ),

    -- 2. Badge counts per user
    badge_counts AS (
        SELECT
            b.UserId,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
            COUNT(*)                                          AS total
        FROM Badges b
        GROUP BY b.UserId
    ),

    -- 3. Post statistics per user
    post_stats AS (
        SELECT
            p.OwnerUserId               AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
            COALESCE(SUM(p.Score),0)                AS total_score,
            MAX(p.CreationDate)                     AS latest_post_date
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),

    -- 4. Comment statistics per user
    comment_stats AS (
        SELECT
            c.UserId               AS UserId,
            COUNT(*)               AS comment_cnt,
            MAX(c.CreationDate)    AS latest_comment_date
        FROM Comments c
        GROUP BY c.UserId
    ),

    -- 5. Vote aggregation per post
    post_votes AS (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes
        FROM Votes v
        GROUP BY v.PostId
    ),

    -- 6. Vote totals per user (via their posts)
    user_votes AS (
        SELECT
            p.OwnerUserId                              AS UserId,
            SUM(COALESCE(pv.upvotes,0))                AS total_upvotes,
            SUM(COALESCE(pv.downvotes,0))              AS total_downvotes
        FROM Posts p
        LEFT JOIN post_votes pv ON pv.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    -- 7. Users that never posted anything
    inactive_users AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation
        FROM Users u
        WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    )

-- 8. Combine active top users with a slice of inactive users
SELECT
    ru.rn,
    ru.Id,
    COALESCE(ru.DisplayName, 'Anonymous')               AS DisplayName,
    ru.Reputation,
    COALESCE(bc.gold,0)                                 AS GoldBadges,
    COALESCE(bc.silver,0)                               AS SilverBadges,
    COALESCE(bc.bronze,0)                               AS BronzeBadges,
    COALESCE(ps.question_cnt,0)                         AS QuestionsPosted,
    COALESCE(ps.answer_cnt,0)                           AS AnswersPosted,
    ps.total_score,
    COALESCE(cs.comment_cnt,0)                          AS CommentsMade,
    uv.total_upvotes,
    uv.total_downvotes,
    CASE
        WHEN ps.latest_post_date IS NULL THEN 'Never'
        ELSE TO_CHAR(ps.latest_post_date, 'YYYY-MM-DD')
    END                                                AS LastPostDate,
    CASE
        WHEN cs.latest_comment_date IS NULL THEN 'Never'
        ELSE TO_CHAR(cs.latest_comment_date, 'YYYY-MM-DD')
    END                                                AS LastCommentDate,
    (SELECT COUNT(*)
     FROM Posts p2
     WHERE p2.OwnerUserId = ru.Id
       AND p2.Tags ILIKE '%<sql>%')                    AS SqlTaggedPosts,
    (SELECT STRING_AGG(DISTINCT t.TagName, ',' ORDER BY cnt DESC)
     FROM (
         SELECT
             unnest(string_to_array(substring(p3.Tags, 2, length(p3.Tags)-2), '><')) AS tag,
             COUNT(*)                                                    AS cnt
         FROM Posts p3
         WHERE p3.OwnerUserId = ru.Id
         GROUP BY tag
         ORDER BY cnt DESC
         LIMIT 5
     ) AS top_tags
     JOIN Tags t ON t.TagName = top_tags.tag)               AS TopTags
FROM ranked_users ru
LEFT JOIN badge_counts bc      ON bc.UserId = ru.Id
LEFT JOIN post_stats ps       ON ps.UserId = ru.Id
LEFT JOIN comment_stats cs    ON cs.UserId = ru.Id
LEFT JOIN user_votes uv       ON uv.UserId = ru.Id
WHERE ru.rn <= 100

UNION ALL

SELECT
    NULL                                              AS rn,
    iu.Id,
    COALESCE(iu.DisplayName, 'Anonymous')             AS DisplayName,
    iu.Reputation,
    0                                                 AS GoldBadges,
    0                                                 AS SilverBadges,
    0                                                 AS BronzeBadges,
    0                                                 AS QuestionsPosted,
    0                                                 AS AnswersPosted,
    0                                                 AS total_score,
    0                                                 AS CommentsMade,
    0                                                 AS total_upvotes,
    0                                                 AS total_downvotes,
    'Never'                                           AS LastPostDate,
    'Never'                                           AS LastCommentDate,
    0                                                 AS SqlTaggedPosts,
    NULL                                              AS TopTags
FROM inactive_users iu
WHERE iu.Reputation > 0
ORDER BY rn NULLS LAST, Reputation DESC
LIMIT 120;  -- 100 active + up to 20 inactive
