WITH top_tags AS (
    SELECT t.TagName, t.Count
    FROM Tags t
    WHERE t.Count > 1000
    ORDER BY t.Count DESC
    LIMIT 20
),
post_months AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        DATE_TRUNC('month', p.CreationDate) AS month,
        UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        COALESCE(p.AnswerCount,0) AS answer_cnt,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS has_accepted
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE '2022-01-01'
),
filtered_posts AS (
    SELECT pm.*
    FROM post_months pm
    JOIN top_tags tt ON tt.TagName = pm.tag
),
user_latest_badge AS (
    SELECT b.UserId,
           b.Name         AS badge_name,
           b.Date         AS badge_date,
           ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM Badges b
),
post_votes AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1
                    WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS net_score,
           COUNT(CASE WHEN v.VoteTypeId = 5 THEN 1 END) AS favorites,
           MAX(v.CreationDate) AS last_vote_date
    FROM Votes v
    GROUP BY v.PostId
),
question_stats AS (
    SELECT 
        fp.month,
        fp.tag,
        COUNT(*)                                            AS question_cnt,
        AVG(fp.Score)                                       AS avg_score,
        SUM(fp.ViewCount)                                   AS total_views,
        SUM(fp.answer_cnt)                                  AS total_answers,
        SUM(fp.has_accepted) * 100.0 / COUNT(*)             AS pct_answered,
        SUM(COALESCE(pv.net_score,0))                       AS total_net_votes,
        SUM(COALESCE(pv.favorites,0))                       AS total_favorites,
        MAX(fp.CreationDate)                                AS latest_question
    FROM filtered_posts fp
    LEFT JOIN post_votes pv ON pv.PostId = fp.Id
    GROUP BY fp.month, fp.tag
),
top_contributors AS (
    SELECT 
        qs.month,
        qs.tag,
        u.Id                                     AS user_id,
        u.DisplayName,
        COUNT(*)                                 AS posted_questions,
        RANK() OVER (PARTITION BY qs.month, qs.tag ORDER BY COUNT(*) DESC) AS rnk
    FROM filtered_posts fp
    JOIN Users u ON u.Id = fp.OwnerUserId
    JOIN question_stats qs ON qs.month = fp.month AND qs.tag = fp.tag
    GROUP BY qs.month, qs.tag, u.Id, u.DisplayName
    HAVING COUNT(*) >= 5
),
base_summary AS (
    SELECT 
        qs.month,
        qs.tag,
        qs.question_cnt,
        ROUND(CAST(qs.avg_score AS numeric),2)      AS avg_score,
        qs.total_views,
        qs.total_answers,
        ROUND(qs.pct_answered,2)                    AS pct_answered,
        qs.total_net_votes,
        qs.total_favorites,
        qs.latest_question,
        tc.user_id,
        tc.DisplayName                              AS top_user,
        tc.posted_questions,
        ub.badge_name,
        ub.badge_date
    FROM question_stats qs
    LEFT JOIN top_contributors tc 
           ON tc.month = qs.month AND tc.tag = qs.tag AND tc.rnk = 1
    LEFT JOIN (
        SELECT UserId, badge_name, badge_date
        FROM user_latest_badge
        WHERE rn = 1
    ) ub ON ub.UserId = tc.user_id
    WHERE qs.question_cnt > 10
)
SELECT * FROM base_summary

UNION ALL

SELECT 
    DATE_TRUNC('month', p.CreationDate) AS month,
    'AllPosts'                           AS tag,
    COUNT(*)                             AS question_cnt,
    AVG(p.Score)                         AS avg_score,
    SUM(p.ViewCount)                     AS total_views,
    SUM(COALESCE(p.AnswerCount,0))       AS total_answers,
    NULL                                  AS pct_answered,
    SUM(COALESCE(vv.net_score,0))        AS total_net_votes,
    SUM(COALESCE(vv.favorites,0))        AS total_favorites,
    MAX(p.CreationDate)                  AS latest_question,
    NULL                                 AS user_id,
    NULL                                 AS top_user,
    NULL                                 AS posted_questions,
    NULL                                 AS badge_name,
    NULL                                 AS badge_date
FROM Posts p
LEFT JOIN post_votes vv ON vv.PostId = p.Id
WHERE p.CreationDate >= DATE '2022-01-01'
GROUP BY DATE_TRUNC('month', p.CreationDate)
ORDER BY month DESC, question_cnt DESC;