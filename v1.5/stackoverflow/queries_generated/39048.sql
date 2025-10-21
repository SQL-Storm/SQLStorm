-- {"query": "39048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 2661} 

WITH monthly_questions AS (
    SELECT
        date_trunc('month', p.CreationDate) AS month,
        tag,
        COUNT(*) AS q_count
    FROM Posts p
    CROSS JOIN LATERAL
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags)-2),
                '><'
            )
        ) AS t(tag)
    WHERE p.PostTypeId = 1
    GROUP BY 1, 2
),
top_tags AS (
    SELECT
        month,
        tag,
        q_count,
        RANK() OVER (PARTITION BY month ORDER BY q_count DESC) AS tag_rank
    FROM monthly_questions
),
selected_tags AS (
    SELECT
        month,
        tag,
        q_count
    FROM top_tags
    WHERE tag_rank <= 5
),
answer_stats AS (
    SELECT
        date_trunc('month', p.CreationDate) AS month,
        COUNT(*)                                        AS a_count,
        AVG(p.Score)                                    AS avg_score,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS median_score
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY 1
),
user_activity AS (
    SELECT
        date_trunc('month', u.CreationDate) AS month,
        u.Id                               AS user_id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS questions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS answers,
        COUNT(v.Id)                                          AS votes_cast,
        SUM((b.Class = 1)::int)                              AS gold_badges,
        SUM((b.Class = 2)::int)                              AS silver_badges,
        SUM((b.Class = 3)::int)                              AS bronze_badges
    FROM Users u
    LEFT JOIN Posts  p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes  v ON v.UserId      = u.Id
    LEFT JOIN Badges b ON b.UserId      = u.Id
    GROUP BY 1, u.Id, u.DisplayName
),
top_users AS (
    SELECT
        month,
        JSON_AGG(obj ORDER BY score_sum DESC) AS top_user_list
    FROM (
        SELECT
            month,
            user_id,
            DisplayName,
            questions,
            answers,
            votes_cast,
            gold_badges,
            silver_badges,
            bronze_badges,
            (questions + answers + votes_cast + gold_badges + silver_badges + bronze_badges) AS score_sum,
            ROW_NUMBER() OVER (PARTITION BY month ORDER BY (questions + answers + votes_cast + gold_badges + silver_badges + bronze_badges) DESC) AS rn,
            JSON_BUILD_OBJECT(
                'user_id',       user_id,
                'display_name',  DisplayName,
                'questions',     questions,
                'answers',       answers,
                'votes_cast',    votes_cast,
                'gold_badges',   gold_badges,
                'silver_badges', silver_badges,
                'bronze_badges', bronze_badges
            ) AS obj
        FROM user_activity
    ) t
    WHERE rn <= 3
    GROUP BY month
)
SELECT
    to_char(st.month, 'YYYY-MM') AS month,
    st.tag,
    st.q_count       AS questions,
    a.a_count        AS answers,
    a.avg_score,
    a.median_score,
    tu.top_user_list
FROM selected_tags st
LEFT JOIN answer_stats a  ON a.month = st.month
LEFT JOIN top_users   tu ON tu.month = st.month
ORDER BY st.month DESC, st.q_count DESC;
