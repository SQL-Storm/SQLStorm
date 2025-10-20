-- {"query": "54027.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1875} 

WITH question_tags AS (
    -- Split the <tag1><tag2> string into one row per tag
    SELECT
        p.Id           AS question_id,
        p.CreationDate,
        regexp_split_to_table(btrim(p.Tags, '<>'), '><') AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
first_answers AS (
    -- Find the first answer for each question
    SELECT
        ans.ParentId AS question_id,
        MIN(ans.CreationDate) AS first_answer_ts
    FROM Posts ans
    WHERE ans.PostTypeId = 2
    GROUP BY ans.ParentId
),
tag_stats AS (
    SELECT
        qt.tag,
        COUNT(DISTINCT qt.question_id)                                                AS num_questions,
        AVG(p.Score)::numeric                                                        AS avg_score,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END)               AS num_with_accepted,
        AVG(
            EXTRACT(EPOCH FROM (fa.first_answer_ts - p.CreationDate))
        ) / 3600                                                                    AS avg_hours_to_first_answer,
        COUNT(ph.PostId)                                                             AS num_close_votes,
        -- Use a JSON aggregate to capture distinct close reason ids per tag
        JSON_AGG(DISTINCT ph.UserId)                                                 AS close_reason_user_ids
    FROM question_tags qt
    JOIN Posts p ON p.Id = qt.question_id
    LEFT JOIN first_answers fa ON fa.question_id = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    GROUP BY qt.tag
),
ranked_tags AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY 1
            ORDER BY num_questions DESC, avg_score DESC
        ) AS rn
    FROM tag_stats
)
SELECT
    tag,
    num_questions,
    ROUND(avg_score, 1)                AS avg_score,
    ROUND(num_with_accepted::numeric / num_questions::numeric * 100, 2) AS pct_accepted,
    ROUND(avg_hours_to_first_answer, 1) AS avg_hours_first_answer,
    num_close_votes,
    close_reason_user_ids
FROM ranked_tags
WHERE rn <= 10
ORDER BY num_questions DESC, avg_score DESC;
