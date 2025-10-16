-- {"query": "24061.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 5696} 

WITH user_posts AS (
    SELECT
        u.Id           AS user_id,
        p.Id           AS post_id,
        p.PostTypeId,
        p.Score,
        p.Title,
        p.Tags
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
),

post_ranked AS (
    SELECT
        user_id,
        post_id,
        title,
        score,
        PostTypeId,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY score DESC) AS rn
    FROM user_posts
),

user_badges AS (
    SELECT
        UserId,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS gold,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS silver,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Badges
    GROUP BY UserId
),

accepted_counts AS (
    SELECT
        ans.OwnerUserId AS user_id,
        COUNT(*) AS accepted_ans
    FROM Posts ans
    JOIN Posts q
      ON ans.ParentId = q.Id
     AND ans.Id = q.AcceptedAnswerId
    GROUP BY ans.OwnerUserId
),

user_comments AS (
    SELECT
        UserId,
        COUNT(*)  AS comment_cnt,
        MIN(Score) AS min_comment_score
    FROM Comments
    GROUP BY UserId
),

worst_comment AS (
    SELECT
        c.UserId,
        c.Id   AS comment_id,
        c.Score,
        c.Text
    FROM Comments c
    WHERE c.Score = (
            SELECT MIN(c2.Score)
            FROM Comments c2
            WHERE c2.UserId = c.UserId
        )
),

user_tags AS (
    SELECT
        u.Id            AS user_id,
        STRING_AGG(DISTINCT tag_text, ', ') AS tag_list,
        COUNT(DISTINCT tag_text)            AS tag_cnt
    FROM Users u
    JOIN Posts p
      ON p.OwnerUserId = u.Id
    JOIN LATERAL
      unnest(regexp_split_to_array(p.Tags, '\\><')) AS tag_text
          ON p.PostTypeId = 1
    GROUP BY u.Id
),

user_stats AS (
    SELECT
        u.Id                              AS user_id,
        u.DisplayName,
        u.Reputation,
        u.LastAccessDate,
        COUNT(p.post_id)                                   AS total_posts,
        COUNT(p.post_id) FILTER (WHERE p.PostTypeId = 2)     AS total_answers,
        ROUND(AVG(p.Score)::numeric, 2)                    AS avg_score,
        pr.post_id                                          AS highest_score_post_id,
        pr.title                                            AS highest_score_post_title
    FROM Users u
    LEFT JOIN user_posts p
      ON p.user_id = u.Id
    LEFT JOIN post_ranked pr
      ON pr.user_id = u.Id
     AND pr.rn = 1
    GROUP BY u.Id,
             u.DisplayName,
             u.Reputation,
             u.LastAccessDate,
             pr.post_id,
             pr.title
),

full_summary AS (
    SELECT
        s.user_id,
        s.DisplayName,
        s.Reputation,
        s.total_posts,
        s.total_answers,
        s.avg_score,
        s.highest_score_post_id,
        s.highest_score_post_title,
        COALESCE(ac.accepted_ans, 0)                           AS accepted_answers,
        CASE
            WHEN s.total_answers > 0
            THEN ROUND(ac.accepted_ans::numeric / s.total_answers, 3)
            ELSE NULL
        END                                                   AS pct_accepted,
        wc.comment_id,
        wc.Score           AS worst_comment_score,
        wc.Text            AS worst_comment_text,
        tg.tag_list,
        tg.tag_cnt,
        ROUND(EXTRACT(EPOCH FROM (NOW() - s.LastAccessDate)) / 86400, 0) AS days_since_last_access,
        c.comment_cnt
    FROM user_stats s
    LEFT JOIN accepted_counts ac
      ON ac.user_id = s.user_id
    LEFT JOIN worst_comment wc
      ON wc.UserId = s.user_id
    LEFT JOIN user_tags tg
      ON tg.user_id = s.user_id
    LEFT JOIN user_comments c
      ON c.UserId = s.user_id
),

high_rep AS (
    SELECT * FROM full_summary WHERE Reputation > 100000
),

low_rep AS (
    SELECT * FROM full_summary WHERE Reputation <= 100000
)

SELECT *
FROM (
        SELECT * FROM high_rep
        UNION ALL
        SELECT * FROM low_rep
     ) AS combined
ORDER BY Reputation DESC
LIMIT 200;
