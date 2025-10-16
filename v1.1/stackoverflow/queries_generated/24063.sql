-- {"query": "24063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2618} 

WITH
-- Split a question's tags into individual rows
tag_split AS (
    SELECT p.Id                 AS post_id,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),

-- Resolve tag ids and ensure we keep questions even if a tag is missing
question_tags AS (
    SELECT ts.post_id,
           t.TagName
    FROM tag_split ts
    LEFT JOIN Tags t ON t.TagName = ts.tag
),

-- Gather per‑question metrics using correlated sub‑queries
question_metrics AS (
    SELECT p.Id          AS question_id,
           p.Title,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 0)          AS pos_comments,
           (SELECT MAX(v.Score) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)   AS max_upvote,
           (SELECT MAX(a.Score) FROM Posts a   WHERE a.ParentId = p.Id AND a.PostTypeId = 2) AS max_ans_score,
           (SELECT MAX(u.Reputation) FROM Users u WHERE u.Id = p.OwnerUserId)                AS owner_rep
    FROM Posts p
    WHERE p.PostTypeId = 1
),

-- Add ranking window functions; keep all tagged rows
question_tag_stats AS (
    SELECT qm.question_id,
           qt.TagName,
           qm.Title,
           qm.Score,
           qm.ViewCount,
           qm.AnswerCount,
           qm.pos_comments,
           qm.max_upvote,
           qm.max_ans_score,
           qm.owner_rep,
           COUNT(*) OVER (PARTITION BY qt.TagName)                           AS tag_cnt,
           ROW_NUMBER() OVER (PARTITION BY qt.TagName
                              ORDER BY qm.max_upvote DESC, qm.Score DESC)   AS tag_rank,
           RANK() OVER (ORDER BY qm.max_upvote DESC, qm.Score DESC)          AS overall_rank
    FROM question_metrics qm
    LEFT JOIN question_tags qt ON qt.post_id = qm.question_id
),

-- Two sets of rows to be merged: top 20 overall, plus questions whose best answer scores > 25
merged_rows AS (
    SELECT *
    FROM question_tag_stats
    WHERE overall_rank <= 20

    UNION ALL

    SELECT qt2.post_id AS question_id,
           qt2.TagName,
           qm2.Title,
           qm2.Score,
           qm2.ViewCount,
           qm2.AnswerCount,
           qm2.pos_comments,
           qm2.max_upvote,
           qm2.max_ans_score,
           qm2.owner_rep,
           COUNT(*) OVER (PARTITION BY qt2.TagName)                          AS tag_cnt,
           ROW_NUMBER() OVER (PARTITION BY qt2.TagName
                              ORDER BY qm2.max_upvote DESC, qm2.Score DESC)  AS tag_rank,
           RANK() OVER (ORDER BY qm2.max_upvote DESC, qm2.Score DESC)       AS overall_rank
    FROM question_metrics qm2
    JOIN question_tags qt2 ON qt2.post_id = qm2.question_id
    WHERE qm2.max_ans_score > 25
)

SELECT
    m.question_id,
    m.TagName,
    m.Title,
    m.Score,
    m.ViewCount,
    m.AnswerCount,
    m.pos_comments,
    m.max_upvote,
    m.max_ans_score,
    m.owner_rep,
    m.tag_cnt,
    m.tag_rank,
    m.overall_rank,
    CASE
        WHEN m.pos_comments > 5 AND m.max_upvote > 200 THEN 'Highly Engaged'
        WHEN m.max_ans_score > 50 THEN 'High Scoring'
        ELSE 'Normal'
    END AS engagement
FROM merged_rows m
ORDER BY m.overall_rank, m.tag_rank
LIMIT 50;
