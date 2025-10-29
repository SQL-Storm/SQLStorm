WITH
recent_posts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
tag_stats AS (
    SELECT
        TRIM(BOTH '<>' FROM tag) AS tag,
        COUNT(*) AS question_cnt
    FROM (
        SELECT
            p.Id,
            p.Tags,
            REGEXP_SPLIT_TO_TABLE(
                REGEXP_REPLACE(TRIM(BOTH '<>' FROM p.Tags), '><', '|', 'g'),
                '\\|'
            ) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) t
    GROUP BY TRIM(BOTH '<>' FROM tag)
),
user_activity AS (
    SELECT
        u.Id                                            AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(b.badge_cnt, 0)                        AS badge_cnt,
        COALESCE(p.post_cnt, 0)                         AS post_cnt,
        COALESCE(c.comment_cnt, 0)                      AS comment_cnt,
        COALESCE(p.last_activity, TIMESTAMP '1970-01-01') AS last_activity,
        (SELECT AVG(p2.AnswerCount)
         FROM Posts p2
         WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS avg_answers_per_q
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS post_cnt, MAX(LastActivityDate) AS last_activity
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS comment_cnt
        FROM Comments
        GROUP BY UserId
    ) c ON u.Id = c.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS badge_cnt
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
),
top_users AS (
    SELECT
        ua.user_id,
        ua.DisplayName,
        ua.Reputation,
        ua.badge_cnt,
        ua.post_cnt,
        ua.comment_cnt,
        ua.last_activity,
        ua.avg_answers_per_q,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.badge_cnt DESC) AS rn
    FROM user_activity ua
    WHERE ua.Reputation > 1000
),
vote_agg AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS vote_score,
        COUNT(*) AS vote_cnt
    FROM Votes v
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '90 days'
    GROUP BY v.PostId
),
question_score AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        COALESCE(p.Score,0) + COALESCE(va.vote_score,0) AS total_score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId
                           ORDER BY COALESCE(p.Score,0) + COALESCE(va.vote_score,0) DESC) AS rank_in_user
    FROM Posts p
    LEFT JOIN vote_agg va ON p.Id = va.PostId
    WHERE p.PostTypeId = 1
),
duplicate_links AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS link_type_name
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
),
top_tags AS (
    SELECT
        ts.tag,
        ts.question_cnt,
        ROW_NUMBER() OVER (ORDER BY ts.question_cnt DESC) AS tag_rank
    FROM tag_stats ts
),
final_set AS (
    SELECT
        tu.rn                                 AS user_rank,
        tu.DisplayName,
        tu.Reputation,
        tu.badge_cnt,
        tu.post_cnt,
        tu.comment_cnt,
        tu.last_activity,
        tu.avg_answers_per_q,
        qs.Title                              AS top_question_title,
        qs.total_score                        AS top_question_score,
        tt.tag,
        tt.question_cnt                       AS tag_question_cnt
    FROM top_users tu
    LEFT JOIN question_score qs
           ON qs.OwnerUserId = tu.user_id
          AND qs.rank_in_user = 1
    LEFT JOIN top_tags tt
           ON tt.tag_rank <= 5
    WHERE tu.rn <= 10

    UNION ALL

    SELECT
        NULL, '---', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
)
SELECT *
FROM final_set
ORDER BY user_rank NULLS LAST, tag_question_cnt DESC NULLS LAST;