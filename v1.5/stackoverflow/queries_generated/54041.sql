-- {"query": "54041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 3099} 

WITH tag_stats AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT q.Id)                                   AS question_count,
        SUM(q.Score)                                           AS total_score,
        AVG(q.AnswerCount)                                     AS avg_answers,
        AVG(q.ViewCount)                                       AS avg_views,
        COUNT(DISTINCT q.OwnerUserId)                          AS unique_users,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)      AS total_upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)      AS total_downvotes,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS total_edits
    FROM
        Tags t
        LEFT JOIN Posts q
            ON q.Tags LIKE ('%<'||t.TagName||'>%' ) AND q.PostTypeId = 1
        LEFT JOIN Votes v
            ON v.PostId = q.Id
        LEFT JOIN PostHistory ph
            ON ph.PostId = q.Id
    GROUP BY
        t.TagName
)
SELECT
    TagName,
    question_count,
    total_score,
    avg_answers,
    avg_views,
    unique_users,
    total_upvotes,
    total_downvotes,
    total_edits,
    RANK() OVER (ORDER BY total_score DESC) AS score_rank
FROM
    tag_stats
ORDER BY
    score_rank
LIMIT 20;
