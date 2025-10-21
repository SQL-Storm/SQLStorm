-- {"query": "54095.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1715} 

WITH question_info AS (
    SELECT
        p.Id              AS qid,
        p.OwnerUserId,
        p.Score,
        p.Tags,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId = 1
),

tag_list AS (
    SELECT
        qid,
        UNNEST(string_to_array(BTRIM(LEFT(REPLACE(Tags, '><','><'), LENGTH(Tags)-2), '<>')) ) AS tag
    FROM question_info
),

tag_counts AS (
    SELECT
        tag,
        COUNT(*) AS question_count
    FROM tag_list
    GROUP BY tag
    ORDER BY question_count DESC
    LIMIT 10
),

user_stats AS (
    SELECT
        q.OwnerUserId,
        COUNT(DISTINCT q.qid)            AS question_count,
        SUM(q.Score)                     AS total_score,
        AVG(q.Score)                     AS avg_score,
        SUM(v.VoteTypeId = 2)::int       AS upvotes,
        SUM(v.VoteTypeId = 3)::int       AS downvotes,
        STRING_AGG(DISTINCT t.tag, ',')   AS tags
    FROM question_info q
    LEFT JOIN Votes v
        ON v.PostId = q.qid
    LEFT JOIN tag_list t
        ON t.qid = q.qid
    GROUP BY q.OwnerUserId
    HAVING COUNT(DISTINCT q.qid) >= 10
),

user_ranks AS (
    SELECT
        us.*,
        NTILE(3) OVER (ORDER BY us.avg_score DESC) AS score_bucket
    FROM user_stats us
)

SELECT
    ur.OwnerUserId,
    u.DisplayName,
    ur.question_count,
    ur.total_score,
    ur.avg_score,
    ur.upvotes,
    ur.downvotes,
    ur.tags,
    ur.score_bucket,
    tc.tag,
    tc.question_count AS tag_used
FROM user_ranks ur
JOIN Users u
    ON u.Id = ur.OwnerUserId
LEFT JOIN tag_counts tc
    ON tc.tag = ANY(string_to_array(ur.tags, ','))
ORDER BY ur.avg_score DESC
LIMIT 50;
