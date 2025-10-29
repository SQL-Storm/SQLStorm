-- {"query": "3434.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1856}
WITH recent_posts AS (
    SELECT *
    FROM Posts
    WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
user_stats AS (
    SELECT
        u.Id                                    AS user_id,
        COALESCE(u.DisplayName, '(anon)')       AS display_name,
        u.Reputation,
        COUNT(DISTINCT b.Id)                    AS badge_cnt,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END)  AS question_score,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END)  AS answer_score,
        COUNT(p.Id)                             AS total_posts,
        AVG(p.ViewCount)                        AS avg_views,
        MAX(p.CreationDate)                     AS last_post_date
    FROM Users u
    LEFT JOIN Badges b   ON b.UserId = u.Id
    LEFT JOIN Posts p    ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_users AS (
    SELECT
        user_id,
        display_name,
        Reputation,
        badge_cnt,
        question_score,
        answer_score,
        total_posts,
        avg_views,
        last_post_date,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, badge_cnt DESC) AS rn
    FROM user_stats
    WHERE Reputation > 1000
),
closed_questions AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS closed_at,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END)       AS close_reason_id
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
close_reasons AS (
    SELECT
        CAST(crt.Id AS varchar)      AS id,
        crt.Name                     AS name
    FROM CloseReasonTypes crt
),
tag_usage AS (
    SELECT
        t.TagName,
        COUNT(pt.post_id) AS usage_cnt
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT
            p.Id AS post_id,
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
        FROM Posts p
        WHERE p.PostTypeId = 1
    ) pt ON pt.tag = t.TagName
    GROUP BY t.TagName
),
user_latest_q AS (
    SELECT
        p.OwnerUserId               AS user_id,
        p.Id                        AS post_id,
        p.CreationDate              AS created_at,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
),
user_closed_info AS (
    SELECT
        ulq.user_id,
        cq.closed_at,
        COALESCE(cr.name, 'None')   AS close_reason
    FROM user_latest_q ulq
    LEFT JOIN closed_questions cq ON cq.PostId = ulq.post_id AND ulq.rn = 1
    LEFT JOIN close_reasons cr    ON cr.id = cq.close_reason_id
)
SELECT
    tu.rn,
    tu.user_id,
    tu.display_name,
    tu.Reputation AS reputation,
    tu.badge_cnt,
    tu.question_score,
    tu.answer_score,
    (tu.total_posts - COALESCE(cq_cnt.closed_cnt,0))          AS open_post_cnt,
    ROUND(tu.avg_views,2)                                     AS avg_views,
    CAST(tu.last_post_date AS varchar)                         AS last_post_date,
    uci.close_reason
FROM top_users tu
LEFT JOIN (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS closed_cnt
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Id IN (SELECT PostId FROM closed_questions)
    GROUP BY p.OwnerUserId
) cq_cnt ON cq_cnt.OwnerUserId = tu.user_id
LEFT JOIN user_closed_info uci ON uci.user_id = tu.user_id
WHERE tu.rn <= 50

UNION ALL

SELECT
    CAST(NULL AS int)        AS rn,
    CAST(NULL AS int)        AS user_id,
    CAST(NULL AS varchar)    AS display_name,
    CAST(NULL AS int)        AS reputation,
    CAST(NULL AS int)        AS badge_cnt,
    CAST(NULL AS int)        AS question_score,
    CAST(NULL AS int)        AS answer_score,
    CAST(NULL AS int)        AS open_post_cnt,
    CAST(NULL AS numeric)    AS avg_views,
    CAST(NULL AS varchar)    AS last_post_date,
    CAST(NULL AS varchar)    AS close_reason
WHERE FALSE

ORDER BY rn;