-- {"query": "3145.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2170}
WITH 
    user_posts AS (
        SELECT 
            u.Id                         AS user_id,
            u.DisplayName                AS display_name,
            u.Reputation,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS question_cnt,
            COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS answer_cnt,
            SUM(p.Score)                 AS total_score,
            MAX(p.CreationDate)          AS last_post_dt
        FROM Users u
        LEFT JOIN Posts p
            ON p.OwnerUserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),

    user_badges AS (
        SELECT 
            b.UserId                     AS user_id,
            COUNT(*) FILTER (WHERE b.Class = 1) AS gold_cnt,
            COUNT(*) FILTER (WHERE b.Class = 2) AS silver_cnt,
            COUNT(*) FILTER (WHERE b.Class = 3) AS bronze_cnt,
            STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS gold_names
        FROM Badges b
        GROUP BY b.UserId
    ),

    tag_usage AS (
        SELECT 
            p.OwnerUserId                AS user_id,
            UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), '><')) AS tag,
            COUNT(*)                     AS tag_cnt
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.Tags IS NOT NULL
        GROUP BY p.OwnerUserId, UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR (CHAR_LENGTH(p.Tags)-2)), '><'))
    ),

    top_tags AS (
        SELECT 
            tu.user_id,
            tu.tag,
            tu.tag_cnt,
            ROW_NUMBER() OVER (PARTITION BY tu.user_id ORDER BY tu.tag_cnt DESC, tu.tag) AS rn
        FROM tag_usage tu
    ),

    recent_votes AS (
        SELECT 
            v.UserId                    AS user_id,
            v.VoteTypeId,
            v.CreationDate,
            ROW_NUMBER() OVER (PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS rn
        FROM Votes v
    ),
    last_vote AS (
        SELECT 
            rv.user_id,
            rv.VoteTypeId,
            rv.CreationDate
        FROM recent_votes rv
        WHERE rv.rn = 1
    ),

    inactive_users AS (
        SELECT 
            u.Id                         AS user_id,
            COALESCE(u.DisplayName, 'Anonymous') AS display_name,
            u.Reputation,
            0 AS question_cnt,
            0 AS answer_cnt,
            0 AS total_score,
            CAST(NULL AS timestamp) AS last_post_dt,
            0 AS gold_cnt,
            0 AS silver_cnt,
            0 AS bronze_cnt,
            CAST(NULL AS varchar) AS gold_names,
            CAST(NULL AS varchar) AS top_tag,
            CAST(NULL AS integer) AS top_tag_cnt,
            CAST(NULL AS integer) AS last_vote_type,
            CAST(NULL AS timestamp) AS last_vote_dt
        FROM Users u
        WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
          AND u.Reputation BETWEEN 1 AND 5000
    ),

    active_users AS (
        SELECT 
            up.user_id,
            COALESCE(up.display_name, 'Anonymous') AS display_name,
            up.Reputation,
            up.question_cnt,
            up.answer_cnt,
            up.total_score,
            up.last_post_dt,
            COALESCE(ub.gold_cnt, 0)   AS gold_cnt,
            COALESCE(ub.silver_cnt, 0) AS silver_cnt,
            COALESCE(ub.bronze_cnt, 0) AS bronze_cnt,
            ub.gold_names,
            tt.tag                      AS top_tag,
            tt.tag_cnt                  AS top_tag_cnt,
            CASE 
                WHEN lv.VoteTypeId = 2 THEN 'Upvote'
                WHEN lv.VoteTypeId = 3 THEN 'Downvote'
                WHEN lv.VoteTypeId = 1 THEN 'AcceptedByOriginator'
                ELSE NULL
            END                         AS last_vote_type,
            lv.CreationDate             AS last_vote_dt
        FROM user_posts up
        LEFT JOIN user_badges ub
            ON ub.user_id = up.user_id
        LEFT JOIN top_tags tt
            ON tt.user_id = up.user_id
           AND tt.rn = 1
        LEFT JOIN last_vote lv
            ON lv.user_id = up.user_id
        WHERE up.Reputation > 10000 
           OR COALESCE(ub.gold_cnt,0) > 0
        GROUP BY
            up.user_id,
            up.display_name,
            up.Reputation,
            up.question_cnt,
            up.answer_cnt,
            up.total_score,
            up.last_post_dt,
            ub.gold_cnt,
            ub.silver_cnt,
            ub.bronze_cnt,
            ub.gold_names,
            tt.tag,
            tt.tag_cnt,
            lv.VoteTypeId,
            lv.CreationDate
    )

SELECT 
    user_id,
    display_name,
    Reputation,
    question_cnt,
    answer_cnt,
    total_score,
    last_post_dt,
    gold_cnt,
    silver_cnt,
    bronze_cnt,
    gold_names,
    top_tag,
    top_tag_cnt,
    last_vote_type,
    last_vote_dt
FROM active_users

UNION ALL

SELECT 
    user_id,
    display_name,
    Reputation,
    question_cnt,
    answer_cnt,
    total_score,
    last_post_dt,
    gold_cnt,
    silver_cnt,
    bronze_cnt,
    gold_names,
    top_tag,
    top_tag_cnt,
    -- cast last_vote_type to text to match active_users' text type
    CAST(last_vote_type AS varchar) AS last_vote_type,
    last_vote_dt
FROM inactive_users

ORDER BY Reputation DESC
LIMIT 100;