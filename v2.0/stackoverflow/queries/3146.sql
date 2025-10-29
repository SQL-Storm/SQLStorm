-- {"query": "3146.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1921}
WITH
recent_posts AS (
    SELECT
        p.Id                               AS post_id,
        p.PostTypeId,
        p.OwnerUserId                      AS owner_user_id,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        COALESCE(p.Tags, '')               AS tags_raw,
        CASE WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
             THEN split_part(substr(p.Tags, 2, length(p.Tags)-2), '><', 1)
             ELSE NULL END                AS first_tag,
        (SELECT MAX(v.CreationDate)
         FROM Votes v
         WHERE v.PostId = p.Id)            AS latest_vote_dt,
        EXISTS (SELECT 1
                FROM PostHistory ph
                WHERE ph.PostId = p.Id
                  AND ph.PostHistoryTypeId IN (4,5,6)) AS has_edit
    FROM Posts p
    WHERE p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
),

user_badges AS (
    SELECT
        u.Id                               AS user_id,
        COUNT(b.UserId)                     AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges,
        STRING_AGG(DISTINCT b.Name, ', ')  AS badge_names
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),

tag_stats AS (
    SELECT
        t.TagName,
        t.Count                                   AS tag_total_posts,
        COALESCE(SUM(p.ViewCount),0)               AS total_views,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.ViewCount),0) DESC) AS view_rank
    FROM Tags t
    LEFT JOIN Posts p
        ON ('<' || REPLACE(p.Tags, '><', '>;<') || '>') LIKE '%' || '<' || t.TagName || '>' || '%'
    GROUP BY t.TagName, t.Count
),

post_votes AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes,
        COUNT(*)                                      AS total_votes,
        MAX(v.CreationDate)                           AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
    GROUP BY v.PostId
),

users_no_posts AS (
    SELECT u.Id, u.DisplayName
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.Id IS NULL
)

SELECT *
FROM (
    SELECT
        rp.post_id,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.tags_raw,
        COALESCE(ub.total_badges,0)                         AS user_badge_total,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        pv.up_votes,
        pv.down_votes,
        pv.total_votes,
        ts.TagName,
        ts.total_views,
        ts.view_rank,
        ROUND(
            (rp.Score * 1.5) +
            (COALESCE(pv.up_votes,0) * 0.8) -
            (COALESCE(pv.down_votes,0) * 1.2) +
            (COALESCE(ub.gold_badges,0) * 5) +
            (COALESCE(ub.silver_badges,0) * 2) +
            (COALESCE(ub.bronze_badges,0) * 1) , 2
        )                                               AS impact_score,
        CASE WHEN rp.has_edit THEN 'Edited' ELSE 'Original' END AS edit_status,
        ROW_NUMBER() OVER (PARTITION BY rp.owner_user_id ORDER BY rp.CreationDate DESC) AS user_question_seq
    FROM recent_posts rp
    LEFT JOIN user_badges ub ON ub.user_id = rp.owner_user_id
    LEFT JOIN post_votes pv ON pv.PostId = rp.post_id
    LEFT JOIN tag_stats ts ON ts.TagName = rp.first_tag
    WHERE rp.PostTypeId = 1
) q

UNION ALL

SELECT *
FROM (
    SELECT
        rp.post_id,
        NULL                                             AS Title,
        rp.CreationDate,
        rp.Score,
        NULL                                             AS ViewCount,
        NULL                                             AS tags_raw,
        COALESCE(ub.total_badges,0)                      AS user_badge_total,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        pv.up_votes,
        pv.down_votes,
        pv.total_votes,
        NULL                                             AS TagName,
        NULL                                             AS total_views,
        NULL                                             AS view_rank,
        ROUND(
            (rp.Score * 2.0) +
            (COALESCE(pv.up_votes,0) * 1.0) -
            (COALESCE(pv.down_votes,0) * 1.5) +
            (COALESCE(ub.gold_badges,0) * 3) , 2
        )                                               AS impact_score,
        CASE WHEN rp.has_edit THEN 'Edited' ELSE 'Original' END AS edit_status,
        ROW_NUMBER() OVER (PARTITION BY rp.owner_user_id ORDER BY rp.CreationDate DESC) AS user_answer_seq
    FROM recent_posts rp
    LEFT JOIN user_badges ub ON ub.user_id = rp.owner_user_id
    LEFT JOIN post_votes pv ON pv.PostId = rp.post_id
    WHERE rp.PostTypeId = 2
) a

UNION ALL

SELECT
    NULL::bigint                AS post_id,
    NULL::text                  AS Title,
    NULL::timestamp             AS CreationDate,
    NULL::integer               AS Score,
    NULL::integer               AS ViewCount,
    NULL::text                  AS tags_raw,
    COALESCE(ub.total_badges,0) AS user_badge_total,
    ub.gold_badges,
    ub.silver_badges,
    ub.bronze_badges,
    NULL::integer               AS up_votes,
    NULL::integer               AS down_votes,
    NULL::integer               AS total_votes,
    NULL::text                  AS TagName,
    NULL::bigint                AS total_views,
    NULL::integer               AS view_rank,
    0.0                         AS impact_score,
    'NoPosts'                   AS edit_status,
    ROW_NUMBER() OVER (ORDER BY u.Id) AS user_seq
FROM users_no_posts u
LEFT JOIN user_badges ub ON ub.user_id = u.Id;