-- {"query": "3420.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1985}
WITH
user_activity AS (
    SELECT
        u.Id                     AS user_id,
        u.DisplayName,
        u.Reputation,
        COALESCE(u.UpVotes,0)    AS total_upvotes,
        COALESCE(u.DownVotes,0)  AS total_downvotes,
        COALESCE(u.Views,0)      AS total_views,
        COUNT(p.Id)              FILTER (WHERE p.PostTypeId = 1) AS question_count,
        COUNT(p.Id)              FILTER (WHERE p.PostTypeId = 2) AS answer_count,
        COUNT(DISTINCT b.Id)     AS badge_count,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvote_votes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvote_votes,
        MAX(p.CreationDate)      AS last_post_date,
        u.CreationDate
    FROM Users u
    LEFT JOIN Posts   p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges  b ON b.UserId = u.Id
    LEFT JOIN Votes   v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate
),
user_rankings AS (
    SELECT
        ua.user_id,
        ua.DisplayName,
        ua.Reputation,
        ua.total_upvotes,
        ua.total_downvotes,
        ua.total_views,
        ua.question_count,
        ua.answer_count,
        ua.badge_count,
        ua.upvote_votes,
        ua.downvote_votes,
        ua.last_post_date,
        ua.CreationDate,
        (
          (ua.total_upvotes - ua.total_downvotes) * 1.0
          + (ua.upvote_votes - ua.downvote_votes) * 0.5
          + ua.badge_count * 10
          + ua.question_count * 2
          + ua.answer_count * 5
        ) / NULLIF( (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ua.CreationDate)) / 86400), 0) AS activity_per_day,
        ROW_NUMBER() OVER (ORDER BY
            (
              ( (ua.total_upvotes - ua.total_downvotes) * 1.0
               + (ua.upvote_votes - ua.downvote_votes) * 0.5
               + ua.badge_count * 10
               + ua.question_count * 2
               + ua.answer_count * 5
              ) / NULLIF( (EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - ua.CreationDate)) / 86400), 0)
            ) DESC) AS activity_rank
    FROM user_activity ua
),
recent_hot_questions AS (
    SELECT
        p.Id                        AS question_id,
        p.Title,
        p.Score,
        p.CreationDate,
        p.OwnerUserId               AS asker_id,
        COALESCE(p.FavoriteCount,0) AS favorite_cnt,
        UNNEST(string_to_array(
                REGEXP_REPLACE(p.Tags, '^<|>$', '', 'g'),
                '><'
            ))                        AS tag_name,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.Score DESC) AS tag_rank
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score >= 10
      AND p.CreationDate > (DATE '2024-10-01' - INTERVAL '30 days')
),
tag_popularity AS (
    SELECT
        tag_name,
        COUNT(DISTINCT question_id) AS question_appearance,
        SUM(score)                  AS total_score,
        AVG(score)                  AS avg_score,
        SUM(favorite_cnt)           AS total_favorites
    FROM recent_hot_questions
    GROUP BY tag_name
),
answer_quality AS (
    SELECT
        a.OwnerUserId            AS answerer_id,
        COUNT(a.Id)              AS answer_count,
        SUM(a.Score)             AS total_answer_score,
        AVG(a.Score)             AS avg_answer_score,
        MAX(a.CreationDate)      AS most_recent_answer,
        COUNT(DISTINCT phq.question_id) FILTER (WHERE a.Score >= 5) AS high_quality_answers
    FROM Posts a
    JOIN recent_hot_questions phq ON phq.question_id = a.ParentId
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
latest_badge AS (
    SELECT
        b.UserId,
        b.Name       AS badge_name,
        b.Class,
        b.Date       AS badge_date
    FROM Badges b
    WHERE b.Date = (
        SELECT MAX(b2.Date)
        FROM Badges b2
        WHERE b2.UserId = b.UserId
    )
),
combined_stats AS (
    SELECT
        ur.user_id,
        ur.DisplayName,
        ur.Reputation,
        ur.question_count,
        ur.answer_count                     AS total_user_answers,
        ur.badge_count,
        ur.activity_per_day,
        ur.activity_rank,
        lb.badge_name,
        lb.Class            AS badge_class,
        lb.badge_date,
        aq.answer_count                       AS user_answer_count,
        aq.total_answer_score,
        aq.avg_answer_score,
        aq.high_quality_answers,
        COALESCE(aq.answer_count,0) / NULLIF(ur.answer_count,0) AS answer_contribution_ratio
    FROM user_rankings ur
    LEFT JOIN latest_badge lb ON lb.UserId = ur.user_id
    LEFT JOIN answer_quality aq ON aq.answerer_id = ur.user_id
)
SELECT
    cs.user_id,
    cs.DisplayName,
    cs.Reputation,
    cs.question_count,
    cs.total_user_answers                       AS answer_count,
    cs.badge_count,
    ROUND(cs.activity_per_day,2)               AS activity_per_day,
    cs.activity_rank,
    cs.badge_name,
    cs.badge_class,
    cs.badge_date,
    cs.user_answer_count                        AS user_answer_count,
    cs.total_answer_score                       AS user_answer_score_sum,
    ROUND(cs.avg_answer_score,2)                AS user_answer_score_avg,
    cs.high_quality_answers,
    ROUND(cs.answer_contribution_ratio,4)       AS answer_contrib_ratio,
    CAST(NULL AS varchar(35))                   AS tag_name,
    CAST(NULL AS int)                           AS tag_question_appearance,
    CAST(NULL AS int)                           AS tag_total_score,
    CAST(NULL AS numeric)                       AS tag_avg_score,
    CAST(NULL AS int)                           AS tag_total_favorites
FROM combined_stats cs
WHERE cs.activity_rank <= 100

UNION ALL

SELECT
    CAST(NULL AS int)                         AS user_id,
    CAST(NULL AS varchar(40))                 AS DisplayName,
    CAST(NULL AS int)                         AS Reputation,
    CAST(NULL AS int)                         AS question_count,
    CAST(NULL AS int)                         AS answer_count,
    CAST(NULL AS int)                         AS badge_count,
    CAST(NULL AS numeric)                     AS activity_per_day,
    CAST(NULL AS int)                         AS activity_rank,
    CAST(NULL AS varchar(50))                 AS badge_name,
    CAST(NULL AS smallint)                    AS badge_class,
    CAST(NULL AS timestamp)                   AS badge_date,
    CAST(NULL AS int)                         AS user_answer_count,
    CAST(NULL AS int)                         AS user_answer_score_sum,
    CAST(NULL AS numeric)                     AS user_answer_score_avg,
    CAST(NULL AS int)                         AS high_quality_answers,
    CAST(NULL AS numeric)                     AS answer_contrib_ratio,
    tp.tag_name,
    tp.question_appearance,
    tp.total_score,
    ROUND(tp.avg_score,2)                     AS tag_avg_score,
    tp.total_favorites
FROM tag_popularity tp
ORDER BY
    activity_rank NULLS LAST,
    tag_question_appearance DESC NULLS LAST
LIMIT 150;