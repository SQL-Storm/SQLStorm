-- {"query": "3332.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2682}
WITH user_posts AS (
    SELECT
        u.Id                                 AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END)                     AS question_cnt,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END)                     AS answer_cnt,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END)                 AS avg_answer_score,
        MAX(p.CreationDate)                                              AS last_post_dt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_counts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS gold_cnt,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS silver_cnt,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS bronze_cnt
    FROM Badges b
    GROUP BY b.UserId
),
top_tag_per_user AS (
    SELECT
        up.user_id,
        t.TagName,
        ROW_NUMBER() OVER (PARTITION BY up.user_id ORDER BY COUNT(*) DESC) AS rn
    FROM user_posts up
    JOIN Posts p ON p.OwnerUserId = up.user_id
               AND p.PostTypeId = 1
               AND p.Tags IS NOT NULL
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) pt
    JOIN Tags t ON t.TagName = pt.tag
    GROUP BY up.user_id, t.TagName
    HAVING COUNT(*) > 0
),
recent_close_votes AS (
    SELECT
        ph.UserId,
        COUNT(*) AS recent_close_cnt
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
    GROUP BY ph.UserId
),
activity_window AS (
    SELECT
        u.Id,
        GREATEST(
            COALESCE(u.LastAccessDate, TIMESTAMP '1970-01-01'),
            COALESCE(MAX(p.LastActivityDate), TIMESTAMP '1970-01-01'),
            COALESCE(MAX(c.CreationDate), TIMESTAMP '1970-01-01')
        ) AS last_activity_dt
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.LastAccessDate
),
base_results AS (
    SELECT
        up.user_id,
        up.DisplayName,
        up.Reputation,
        up.question_cnt,
        up.answer_cnt,
        ROUND(CAST(up.avg_answer_score AS numeric), 2)                AS avg_answer_score,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        COALESCE(tp.TagName, 'N/A')                           AS top_tag,
        rc.recent_close_cnt,
        aw.last_activity_dt,
        CASE
            WHEN up.Reputation >= 20000 THEN 'Elite'
            WHEN up.Reputation >= 10000 THEN 'Veteran'
            WHEN up.Reputation >= 1000  THEN 'Experienced'
            ELSE 'Newbie'
        END                                                   AS reputation_tier,
        CONCAT('User ', up.user_id, ': ', up.DisplayName)    AS label,
        (SELECT COUNT(*) FROM Votes v
            WHERE v.UserId = up.user_id AND v.VoteTypeId = 2) AS upvotes_given,
        (SELECT COUNT(*) FROM Posts p2
            WHERE p2.OwnerUserId = up.user_id
              AND p2.PostTypeId = 2
              AND p2.Score > 10)                              AS high_scoring_answers,
        (SELECT MAX(v2.CreationDate) FROM Votes v2
            WHERE v2.UserId = up.user_id)                     AS last_vote_dt
    FROM user_posts up
    LEFT JOIN badge_counts bc            ON bc.UserId = up.user_id
    LEFT JOIN top_tag_per_user tp        ON tp.user_id = up.user_id AND tp.rn = 1
    LEFT JOIN recent_close_votes rc     ON rc.UserId = up.user_id
    LEFT JOIN activity_window aw         ON aw.Id = up.user_id
    WHERE up.Reputation IS NOT NULL
    GROUP BY
        up.user_id,
        up.DisplayName,
        up.Reputation,
        up.question_cnt,
        up.answer_cnt,
        up.avg_answer_score,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        tp.TagName,
        rc.recent_close_cnt,
        aw.last_activity_dt
),
low_tier_results AS (
    SELECT
        up.user_id,
        up.DisplayName,
        up.Reputation,
        up.question_cnt,
        up.answer_cnt,
        ROUND(CAST(up.avg_answer_score AS numeric), 2)                AS avg_answer_score,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        COALESCE(tp.TagName, 'N/A')                           AS top_tag,
        rc.recent_close_cnt,
        aw.last_activity_dt,
        'LowTier'                                             AS reputation_tier,
        CONCAT('User ', up.user_id, ': ', up.DisplayName)    AS label,
        (SELECT COUNT(*) FROM Votes v
            WHERE v.UserId = up.user_id AND v.VoteTypeId = 2) AS upvotes_given,
        (SELECT COUNT(*) FROM Posts p2
            WHERE p2.OwnerUserId = up.user_id
              AND p2.PostTypeId = 2
              AND p2.Score > 10)                              AS high_scoring_answers,
        (SELECT MAX(v2.CreationDate) FROM Votes v2
            WHERE v2.UserId = up.user_id)                     AS last_vote_dt
    FROM user_posts up
    LEFT JOIN badge_counts bc            ON bc.UserId = up.user_id
    LEFT JOIN top_tag_per_user tp        ON tp.user_id = up.user_id AND tp.rn = 1
    LEFT JOIN recent_close_votes rc     ON rc.UserId = up.user_id
    LEFT JOIN activity_window aw         ON aw.Id = up.user_id
    WHERE up.Reputation < 1000
    GROUP BY
        up.user_id,
        up.DisplayName,
        up.Reputation,
        up.question_cnt,
        up.answer_cnt,
        up.avg_answer_score,
        bc.gold_cnt,
        bc.silver_cnt,
        bc.bronze_cnt,
        tp.TagName,
        rc.recent_close_cnt,
        aw.last_activity_dt
)
SELECT *
FROM (
    SELECT * FROM base_results
    ORDER BY Reputation DESC
    LIMIT 100
) t1
UNION ALL
SELECT *
FROM (
    SELECT * FROM low_tier_results
    ORDER BY Reputation DESC
    LIMIT 50
) t2
ORDER BY Reputation DESC;