WITH post_tag_table AS (
    SELECT
        p.Id AS post_id,
        trim(both '<>' FROM t.value) AS tag_name
    FROM Posts p,
    LATERAL (
        SELECT value
        FROM (
            SELECT UNNEST(string_to_array(p.Tags, '><')) AS value
        ) s
    ) t
),
tag_stats AS (
    SELECT
        tag_name,
        COUNT(DISTINCT pt.post_id) AS question_count,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN pt.post_id END) AS accepted_question_count,
        ROUND(
            1.0 * COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN pt.post_id END) /
            NULLIF(COUNT(DISTINCT pt.post_id), 0)
        , 2) AS accepted_ratio
    FROM post_tag_table pt
    JOIN Posts p ON p.Id = pt.post_id AND p.PostTypeId = 1
    GROUP BY tag_name
),
user_stats AS (
    SELECT
        u.Id AS user_id,
        u.DisplayName,
        COUNT(DISTINCT q.Id) AS user_questions,
        COUNT(DISTINCT a.Id) AS user_answers,
        SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS user_answer_upvotes,
        RANK() OVER (ORDER BY SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) DESC) AS ranking
    FROM Users u
    LEFT JOIN Posts q ON q.OwnerUserId = u.Id AND q.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
accepted_by_user AS (
    SELECT
        u.Id AS user_id,
        COUNT(DISTINCT a.Id) AS accepted_answers_given
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Posts q ON q.AcceptedAnswerId = a.Id
    GROUP BY u.Id
),
user_tag_view AS (
    SELECT
        us.user_id,
        us.DisplayName,
        us.user_questions,
        us.user_answers,
        us.user_answer_upvotes,
        us.ranking,
        COALESCE(ab.accepted_answers_given, 0) AS accepted_answers_given,
        t.tag_name,
        t.question_count,
        t.accepted_question_count,
        t.accepted_ratio,
        CASE
            WHEN us.user_answers > 1000 THEN 'Prolific'
            WHEN us.user_answers BETWEEN 100 AND 1000 THEN 'Active'
            ELSE 'Newbie'
        END AS activity_level,
        ('User ' || us.user_id || ' - ' || us.DisplayName) AS user_tag
    FROM user_stats us
    LEFT JOIN accepted_by_user ab ON ab.user_id = us.user_id
    LEFT JOIN LATERAL (
        SELECT tag_name, question_count, accepted_question_count, accepted_ratio
        FROM tag_stats
        ORDER BY accepted_ratio DESC
        LIMIT 5
    ) t ON TRUE
)
SELECT *
FROM user_tag_view
UNION ALL
SELECT
    CAST(NULL AS integer) AS user_id,
    CAST(NULL AS text) AS DisplayName,
    CAST(NULL AS bigint) AS user_questions,
    CAST(NULL AS bigint) AS user_answers,
    CAST(NULL AS bigint) AS user_answer_upvotes,
    CAST(NULL AS bigint) AS ranking,
    CAST(NULL AS bigint) AS accepted_answers_given,
    tag_name,
    question_count,
    accepted_question_count,
    accepted_ratio,
    CAST(NULL AS text) AS activity_level,
    CAST(NULL AS text) AS user_tag
FROM tag_stats
ORDER BY
    ranking NULLS LAST,
    accepted_ratio DESC,
    user_id;