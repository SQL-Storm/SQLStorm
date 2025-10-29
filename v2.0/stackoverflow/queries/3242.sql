-- {"query": "3242.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2785}
WITH 
TagMonthlyStats AS (
    SELECT
        t.TagName,
        CAST(EXTRACT(YEAR FROM p.CreationDate) AS INT)   AS yr,
        CAST(EXTRACT(MONTH FROM p.CreationDate) AS INT)  AS mo,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1)                AS question_cnt,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2)                AS answer_cnt,
        SUM(p.Score)                                           AS total_score,
        ROW_NUMBER() OVER (
            PARTITION BY CAST(EXTRACT(YEAR FROM p.CreationDate) AS INT),
                         CAST(EXTRACT(MONTH FROM p.CreationDate) AS INT)
            ORDER BY SUM(p.Score) DESC
        )                                                      AS rank_in_month
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
    ) AS tlist ON TRUE
    JOIN Tags t ON t.TagName = tlist.tag
    WHERE p.PostTypeId IN (1,2)
    GROUP BY t.TagName,
             CAST(EXTRACT(YEAR FROM p.CreationDate) AS INT),
             CAST(EXTRACT(MONTH FROM p.CreationDate) AS INT)
),
TopTags AS (
    SELECT *
    FROM TagMonthlyStats
    WHERE rank_in_month <= 5
),
UserActivity AS (
    SELECT
        u.Id                            AS user_id,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions_asked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers_given,
        COALESCE(SUM(v.up_votes),0)                     AS total_upvotes,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)    AS has_gold_badge,
        COALESCE( (
            SELECT MAX(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.PostId = p_max.Id
              AND ph.PostHistoryTypeId = 10
        ), TIMESTAMP '1970-01-01')             AS last_closed_date
    FROM Users u
    LEFT JOIN LATERAL (
        -- pick a representative post per user for the correlated subquery usage
        SELECT p2.*
        FROM Posts p2
        WHERE p2.OwnerUserId = u.Id
        ORDER BY p2.CreationDate DESC
        LIMIT 1
    ) p_max ON TRUE
    LEFT JOIN Posts p            ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS up_votes
        FROM Votes
        WHERE VoteTypeId = 2
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    LEFT JOIN Badges b          ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, p_max.Id
),
RecentClosedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        ph.Comment                                      AS close_reason,
        ROW_NUMBER() OVER (PARTITION BY ph.Comment
                           ORDER BY p.CreationDate DESC) AS rn_per_reason
    FROM Posts p
    JOIN PostHistory ph
          ON ph.PostId = p.Id
         AND ph.PostHistoryTypeId = 10
    WHERE p.CreationDate >= (DATE '2024-10-01' - INTERVAL '30' DAY)
)

SELECT
    tt.TagName,
    tt.yr,
    tt.mo,
    tt.question_cnt,
    tt.answer_cnt,
    tt.total_score,
    ua.DisplayName,
    ua.questions_asked,
    ua.answers_given,
    ua.total_upvotes,
    CASE WHEN ua.has_gold_badge = 1 THEN 'Gold' ELSE 'NoGold' END AS gold_badge_status,
    COALESCE(rcp.Title,          'N/A')               AS recent_closed_title,
    COALESCE(rcp.close_reason,  'None')              AS recent_close_reason,
    ('Tag ' || tt.TagName || ' in ' ||
           CAST(tt.yr AS VARCHAR) || '-' || LPAD(CAST(COALESCE(tt.mo,0) AS VARCHAR),2,'0'))      AS tag_period_label,
    (SELECT COUNT(*)
     FROM Comments c
     WHERE c.PostId = rcp.Id
       AND c.Score > 0)                               AS positive_comment_cnt
FROM TopTags tt
LEFT JOIN UserActivity ua
       ON ua.user_id = (
            SELECT p2.OwnerUserId
            FROM Posts p2
            WHERE p2.Tags ILIKE '%'||tt.TagName||'%'
              AND p2.OwnerUserId IS NOT NULL
            ORDER BY p2.Score DESC
            LIMIT 1
       )
LEFT JOIN RecentClosedPosts rcp
       ON rcp.rn_per_reason = 1
      AND rcp.close_reason = (
            SELECT ph2.Comment
            FROM PostHistory ph2
            JOIN Posts p3 ON p3.Id = ph2.PostId
            WHERE ph2.PostHistoryTypeId = 10
              AND p3.Tags ILIKE '%'||tt.TagName||'%'
            ORDER BY p3.CreationDate DESC
            LIMIT 1
      )

UNION ALL

SELECT
    t.TagName,
    CAST(EXTRACT(YEAR FROM p.CreationDate) AS INT)   AS yr,
    CAST(EXTRACT(MONTH FROM p.CreationDate) AS INT)  AS mo,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1)  AS question_cnt,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2)  AS answer_cnt,
    SUM(p.Score)                              AS total_score,
    NULL AS DisplayName,
    NULL AS questions_asked,
    NULL AS answers_given,
    NULL AS total_upvotes,
    NULL AS gold_badge_status,
    NULL AS recent_closed_title,
    NULL AS recent_close_reason,
    NULL AS tag_period_label,
    NULL AS positive_comment_cnt
FROM Posts p
JOIN LATERAL (
    SELECT UNNEST(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
) AS tlist ON TRUE
JOIN Tags t ON t.TagName = tlist.tag
WHERE p.CreationDate >= (DATE '2024-10-01' - INTERVAL '90' DAY)
GROUP BY t.TagName,
         CAST(EXTRACT(YEAR FROM p.CreationDate) AS INT),
         CAST(EXTRACT(MONTH FROM p.CreationDate) AS INT)
HAVING COUNT(*) > 100
ORDER BY yr DESC, mo DESC, total_score DESC NULLS LAST
LIMIT 100;