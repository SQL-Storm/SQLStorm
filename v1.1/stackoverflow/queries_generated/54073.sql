-- {"query": "54073.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1547} 
WITH question_posts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.CreationDate,
        unnest(regexp_split_to_array(p.Tags, '><')) AS tag,
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        p.AnswerCount
    FROM Posts p
    JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
tag_stats AS (
    SELECT
        qp.tag,
        COUNT(*)                                 AS question_count,
        SUM(qp.AnswerCount)                      AS total_answers,
        AVG(qp.Score)                            AS avg_score,
        MAX(qp.CreationDate)                     AS last_post_date,
        STRING_AGG(DISTINCT qp.DisplayName, ', ') AS user_list
    FROM question_posts qp
    GROUP BY qp.tag
),
tag_rank AS (
    SELECT
        tag,
        question_count,
        RANK() OVER (ORDER BY question_count DESC) AS rank
    FROM tag_stats
)
SELECT
    tr.rank,
    tr.tag,
    tr.question_count,
    ts.total_answers,
    ROUND(ts.avg_score::numeric, 2)         AS avg_score,
    ts.last_post_date,
    ts.user_list
FROM tag_rank tr
JOIN tag_stats ts ON ts.tag = tr.tag
ORDER BY tr.rank
LIMIT 20;