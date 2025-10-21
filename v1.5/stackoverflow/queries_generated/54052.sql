-- {"query": "54052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 2189} 
WITH post_stats AS (
    SELECT
        p.Id,
        DATE_TRUNC('month', p.CreationDate) AS month,
        CASE WHEN pt.Id = 1 THEN 1 ELSE 0 END AS is_question,
        CASE WHEN pt.Id = 2 THEN 1 ELSE 0 END AS is_answer,
        p.Score,
        p.ViewCount,
        CASE
            WHEN p.Tags IS NULL OR p.Tags = '' THEN 0
            ELSE array_length(
                regexp_split_to_array(
                    substring(p.Tags, 2, char_length(p.Tags)-2),
                    '\\s*>\\s*<'
                ),
                1
            )
        END AS tag_count
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
vote_counts AS (
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS downvotes,
        COUNT(*) AS total_votes
    FROM Votes
    GROUP BY PostId
),
comment_counts AS (
    SELECT PostId, COUNT(*) AS comment_count
    FROM Comments
    GROUP BY PostId
)
SELECT
    month,
    COUNT(DISTINCT CASE WHEN is_question = 1 THEN Id END) AS questions,
    COUNT(DISTINCT CASE WHEN is_answer = 1 THEN Id END) AS answers,
    COUNT(DISTINCT Id) AS total_posts,
    SUM(total_votes) AS total_votes,
    SUM(upvotes) AS total_upvotes,
    SUM(downvotes) AS total_downvotes,
    AVG(score) AS avg_score,
    AVG(tag_count) FILTER (WHERE is_question = 1) AS avg_tags_per_question,
    MAX(viewcount) AS max_views,
    MAX(score) AS max_score,
    MIN(score) AS min_score,
    RANK() OVER (ORDER BY COUNT(DISTINCT Id) DESC) AS rank
FROM post_stats
LEFT JOIN vote_counts USING (Id)
LEFT JOIN comment_counts USING (Id)
GROUP BY month
ORDER BY month;