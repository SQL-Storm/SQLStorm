-- {"query": "3805.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2106} 

WITH top_users AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation IS NOT NULL
),
user_badge_stats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS total_badges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze
    FROM Badges b
    GROUP BY b.UserId
),
user_post_stats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS questions,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS answers,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS avg_q_score,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS avg_a_score,
        MAX(p.CreationDate) AS latest_post_date
    FROM Posts p
    GROUP BY p.OwnerUserId
),
recent_votes AS (
    SELECT 
        v.PostId,
        vt.Name AS VoteType,
        v.UserId,
        v.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY v.PostId ORDER BY v.CreationDate DESC) AS rn
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
),
top_votes AS (
    SELECT 
        rv.PostId,
        rv.VoteType,
        rv.UserId,
        rv.CreationDate
    FROM recent_votes rv
    WHERE rv.rn = 1
),
question_tag_agg AS (
    SELECT 
        p.Id AS QuestionId,
        UNNEST(STRING_TO_ARRAY(SUBSTR(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS Tag,
        p.Score,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_popularity AS (
    SELECT 
        t.TagName AS Tag,
        COUNT(DISTINCT qt.QuestionId) AS question_cnt,
        AVG(qt.Score) AS avg_score,
        MAX(qt.CreationDate) AS recent_activity
    FROM question_tag_agg qt
    JOIN Tags t ON t.TagName = qt.Tag
    GROUP BY t.TagName
),
final AS (
    SELECT 
        tu.Id,
        tu.DisplayName,
        tu.Reputation,
        COALESCE(ubs.total_badges, 0) AS total_badges,
        COALESCE(ubs.gold, 0) AS gold_badges,
        COALESCE(ups.questions, 0) AS question_count,
        COALESCE(ups.answers, 0) AS answer_count,
        COALESCE(ups.avg_q_score, 0) AS avg_question_score,
        COALESCE(ups.avg_a_score, 0) AS avg_answer_score,
        COALESCE(tv.VoteType, 'None') AS latest_vote_type,
        COALESCE(tv.CreationDate, TIMESTAMP '1970-01-01') AS latest_vote_date,
        tp.Tag,
        tp.question_cnt AS tag_question_cnt,
        tp.avg_score AS tag_avg_score,
        tp.recent_activity AS tag_recent_activity,
        ROW_NUMBER() OVER (PARTITION BY tu.Id ORDER BY tp.question_cnt DESC NULLS LAST) AS tag_rank
    FROM top_users tu
    LEFT JOIN user_badge_stats ubs ON ubs.UserId = tu.Id
    LEFT JOIN user_post_stats ups ON ups.UserId = tu.Id
    LEFT JOIN LATERAL (
        SELECT 
            p.Id
        FROM Posts p
        WHERE p.OwnerUserId = tu.Id
        ORDER BY p.CreationDate DESC
        LIMIT 1
    ) latest_post ON TRUE
    LEFT JOIN top_votes tv ON tv.PostId = latest_post.Id
    LEFT JOIN LATERAL (
        SELECT 
            pt.Tag,
            pt.question_cnt,
            pt.avg_score,
            pt.recent_activity
        FROM tag_popularity pt
        ORDER BY pt.question_cnt DESC
        LIMIT 3
    ) tp ON TRUE
    WHERE tu.rn <= 100
)
SELECT *
FROM final
WHERE tag_rank IS NOT NULL
ORDER BY 
    Reputation DESC,
    total_badges DESC NULLS LAST,
    tag_question_cnt DESC
LIMIT 200;
