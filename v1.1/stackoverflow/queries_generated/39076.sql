-- {"query": "39076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 1398} 

WITH
-- Extract individual tags from each question
TagList AS (
    SELECT
        p.Id                             AS QuestionId,
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        )                                AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1
),
-- Gather answer statistics
AnswerStats AS (
    SELECT
        a.ParentId                       AS QuestionId,
        a.Id                             AS AnswerId,
        a.Score                          AS AnswerScore,
        a.CreationDate                   AS AnswerDate,
        u.Reputation                     AS AnswererReputation
    FROM Posts a
    JOIN Users u
      ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
-- Filter to only accepted answers and join to tags
AcceptedByTag AS (
    SELECT
        tl.Tag,
        ast.AnswerId,
        ast.AnswerScore,
        ast.AnswerDate,
        ast.AnswererReputation
    FROM TagList tl
    JOIN AnswerStats ast
      ON ast.QuestionId = tl.QuestionId
    JOIN Posts q
      ON q.Id = tl.QuestionId
     AND q.AcceptedAnswerId = ast.AnswerId
),
-- Compute per‐tag analytics
TagMetrics AS (
    SELECT
        Tag,
        COUNT(*)                               AS TotalAccepted,
        AVG(AnswerScore)                       AS AvgScore,
        percentile_cont(0.5) WITHIN GROUP
            (ORDER BY AnswerScore)             AS MedianScore,
        AVG(AnswererReputation)                AS AvgReputation,
        MAX(AnswerScore)                       AS MaxScore,
        MIN(AnswerScore)                       AS MinScore
    FROM AcceptedByTag
    GROUP BY Tag
),
-- Rank tags and pick top 10 by average score
TopTags AS (
    SELECT
        tm.*,
        DENSE_RANK() OVER (ORDER BY tm.AvgScore DESC) AS ScoreRank
    FROM TagMetrics tm
),
FinalSelection AS (
    SELECT *
    FROM TopTags
    WHERE ScoreRank <= 10
)
-- Output as a pretty JSON array
SELECT
    jsonb_pretty(
        jsonb_agg(to_jsonb(FinalSelection) ORDER BY ScoreRank)
    ) AS TopTagsAcceptedAnswerStats
FROM FinalSelection;
