-- {"query": "3234.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1610} 

/*  Complex performance‑benchmark query over the StackOverflow schema  */
WITH RECURSIVE tag_hierarchy AS (
    /*  Simulate a tag hierarchy by splitting the Tags column of questions
        and bubbling up the most frequent tag per user  */
    SELECT
        p.OwnerUserId      AS user_id,
        unnest(string_to_array(trim(both '<>' from p.Tags), '><')) AS tag,
        1                  AS depth
    FROM Posts p
    WHERE p.PostTypeId = 1                         -- questions only
      AND p.OwnerUserId IS NOT NULL
    UNION ALL
    SELECT
        th.user_id,
        t.TagName,
        th.depth + 1
    FROM tag_hierarchy th
    JOIN Tags t ON t.TagName = th.tag
    WHERE th.depth < 3
),
user_posts AS (
    SELECT
        u.Id                                 AS user_id,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1)               AS question_cnt,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2)               AS answer_cnt,
        SUM(COALESCE(p.Score,0))                                 AS total_score,
        MAX(p.CreationDate)                                      AS last_post_date,
        MAX(p.LastActivityDate)                                  AS last_activity_date,
        COALESCE(
            MAX(p.LastEditDate) FILTER (WHERE p.LastEditDate IS NOT NULL),
            MAX(p.CreationDate)
        )                                                         AS most_recent_edit
    FROM Users u
    LEFT JOIN Posts p
      ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
user_badges AS (
    SELECT
        b.UserId                                   AS user_id,
        COUNT(*) FILTER (WHERE b.Class = 1)        AS gold_cnt,
        COUNT(*) FILTER (WHERE b.Class = 2)        AS silver_cnt,
        COUNT(*) FILTER (WHERE b.Class = 3)        AS bronze_cnt,
        STRING_AGG(DISTINCT b.Name, ', ')          AS badge_list
    FROM Badges b
    GROUP BY b.UserId
),
user_votes AS (
    SELECT
        v.PostId                                   AS post_id,
        SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS up_votes,
        SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS down_votes,
        MAX(v.CreationDate)                        AS last_vote_date
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
post_engagement AS (
    SELECT
        p.Id                                         AS post_id,
        p.PostTypeId,
        COALESCE(v.up_votes,0)                       AS up_votes,
        COALESCE(v.down_votes,0)                     AS down_votes,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS comment_cnt,
        (SELECT COUNT(*) FROM PostHistory ph
            WHERE ph.PostId = p.Id
              AND ph.PostHistoryTypeId IN (4,5,6)    -- edits
        )                                            AS edit_cnt,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate
    FROM Posts p
    LEFT JOIN user_votes v ON v.post_id = p.Id
),
top_tags AS (
    SELECT
        th.user_id,
        th.tag,
        COUNT(*)                                     AS tag_uses,
        ROW_NUMBER() OVER (PARTITION BY th.user_id ORDER BY COUNT(*) DESC) AS rn
    FROM tag_hierarchy th
    GROUP BY th.user_id, th.tag
),
ranked_users AS (
    SELECT
        up.user_id,
        up.DisplayName,
        up.Reputation,
        up.question_cnt,
        up.answer_cnt,
        up.total_score,
        ub.gold_cnt,
        ub.silver_cnt,
        ub.bronze_cnt,
        ub.badge_list,
        pe.up_votes,
        pe.down_votes,
        pe.comment_cnt,
        pe.edit_cnt,
        pe.Score                AS post_score,
        pe.ViewCount,
        pe.FavoriteCount,
        pe.CreationDate,
        pe.LastActivityDate,
        CASE
            WHEN up.Reputation > 200000 THEN 'Legendary'
            WHEN up.Reputation > 100000 THEN 'Veteran'
            WHEN up.Reputation > 50000  THEN 'Experienced'
            ELSE 'Intermediate'
        END                     AS tier,
        COALESCE(tt.tag, 'none') AS favorite_tag
    FROM user_posts up
    LEFT JOIN user_badges ub ON ub.user_id = up.user_id
    LEFT JOIN post_engagement pe ON pe.PostId = up.user_id   -- purposely mismatched to force outer join cost
    LEFT JOIN (
        SELECT user_id, tag FROM top_tags WHERE rn = 1
    ) tt ON tt.user_id = up.user_id
)
SELECT *
FROM ranked_users
WHERE (question_cnt > 10 OR answer_cnt > 50)
  AND (total_score IS NOT NULL AND total_score <> 0)
  AND (COALESCE(gold_cnt,0) + COALESCE(silver_cnt,0) + COALESCE(bronze_cnt,0)) > 5
  AND (favorite_tag <> 'none')
ORDER BY
    Reputation DESC,
    question_cnt + answer_cnt DESC,
    total_score DESC
LIMIT 100
OFFSET 0
UNION ALL
SELECT
    NULL AS user_id,
    'Aggregated Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(question_cnt) AS question_cnt,
    SUM(answer_cnt)   AS answer_cnt,
    SUM(total_score)  AS total_score,
    SUM(gold_cnt)     AS gold_cnt,
    SUM(silver_cnt)   AS silver_cnt,
    SUM(bronze_cnt)   AS bronze_cnt,
    STRING_AGG(DISTINCT badge_list, '; ') AS badge_list,
    NULL AS up_votes,
    NULL AS down_votes,
    NULL AS comment_cnt,
    NULL AS edit_cnt,
    NULL AS post_score,
    NULL AS ViewCount,
    NULL AS FavoriteCount,
    NULL AS CreationDate,
    NULL AS LastActivityDate,
    NULL AS tier,
    NULL AS favorite_tag
FROM ranked_users
WHERE tier = 'Legendary';
