-- {"query": "24038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3939} 
WITH per_user AS (
    SELECT u.id              AS user_id,
           COALESCE(u.displayname,'unregistered') AS user_name,
           u.reputation,
           COALESCE(np.qcnt,0)  AS question_cnt,
           COALESCE(ap.acnt,0)  AS answer_cnt,
           COALESCE(ps.tscore,0) AS total_score,
           COALESCE(b.bcnt,0)  AS badge_cnt,
           COALESCE(pa.last_act,pa.created_at) AS last_activity
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId,
               COUNT(*) AS qcnt
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) np ON np.OwnerUserId = u.id
    LEFT JOIN (
        SELECT OwnerUserId,
               COUNT(*) AS acnt
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) ap ON ap.OwnerUserId = u.id
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(Score) AS tscore
        FROM Posts
        WHERE PostTypeId IN (1,2)
        GROUP BY OwnerUserId
    ) ps ON ps.OwnerUserId = u.id
    LEFT JOIN (
        SELECT UserId,
               COUNT(*) AS bcnt
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.id
    LEFT JOIN (
        SELECT OwnerUserId,
               MAX(LastActivityDate) AS last_act,
               MAX(CreationDate)     AS created_at
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) pa ON pa.OwnerUserId = u.id
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY total_score DESC, reputation DESC) AS rnk
    FROM per_user
),
summary AS (
    SELECT  r.user_id,
            r.user_name || ' (' || r.reputation || ')'        AS user_label,
            r.total_score,
            r.question_cnt,
            r.answer_cnt,
            r.badge_cnt,
            r.last_activity,
            r.rnk                                       AS rank,
            (SELECT COUNT(*)
             FROM PostLinks l
             JOIN Posts p ON l.PostId = p.Id
             WHERE p.OwnerUserId = r.user_id
               AND p.PostTypeId = 1
               AND l.LinkTypeId = 3)                 AS duplicate_link_cnt,
            (SELECT COUNT(*)
             FROM Comments c
             JOIN Posts p ON c.PostId = p.Id
             WHERE p.OwnerUserId = r.user_id)        AS comment_cnt,
            CASE WHEN r.total_score > 1000 THEN 'High' ELSE 'Low' END AS score_category,
            1                                           AS source_flag
    FROM ranked r
    WHERE r.rnk <= 20

    UNION ALL

    SELECT  r.user_id,
            r.user_name || ' (' || r.reputation || ')'        AS user_label,
            r.total_score,
            r.question_cnt,
            r.answer_cnt,
            r.badge_cnt,
            r.last_activity,
            r.rnk                                       AS rank,
            (SELECT COUNT(*)
             FROM PostLinks l
             JOIN Posts p ON l.PostId = p.Id
             WHERE p.OwnerUserId = r.user_id
               AND p.PostTypeId = 1
               AND l.LinkTypeId = 3)                 AS duplicate_link_cnt,
            (SELECT COUNT(*)
             FROM Comments c
             JOIN Posts p ON c.PostId = p.Id
             WHERE p.OwnerUserId = r.user_id)        AS comment_cnt,
            CASE WHEN r.total_score > 1000 THEN 'High' ELSE 'Low' END AS score_category,
            2                                           AS source_flag
    FROM ranked r
    WHERE r.badge_cnt > 50
)
SELECT *
FROM summary
ORDER BY rank, source_flag;