-- {"query": "54099.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1473} 
WITH question_tags AS (
    SELECT p.Id AS QuestionId,
           p.Tags,
           p.Score,
           p.ViewCount,
           p.CreationDate,
           p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1
),
tag_instances AS (
    SELECT q.QuestionId,
           TRIM(BOTH FROM UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><'))) AS TagName,
           q.Score,
           q.ViewCount
    FROM question_tags q
),
tag_stats AS (
    SELECT ti.TagName,
           COUNT(*) AS NumQuestions,
           AVG(ti.Score) AS AvgScore,
           SUM(ti.ViewCount) AS TotalViews,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ti.Score) AS MedianScore
    FROM tag_instances ti
    GROUP BY ti.TagName
),
close_votes_per_tag AS (
    SELECT ti.TagName,
           COUNT(*) AS CloseVoteCount
    FROM tag_instances ti
    JOIN PostHistory ph ON ph.PostId = ti.QuestionId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ti.TagName
)
SELECT ts.TagName,
       ts.NumQuestions,
       ts.AvgScore,
       ts.TotalViews,
       ts.MedianScore,
       COALESCE(cv.CloseVoteCount, 0) AS CloseVotes
FROM tag_stats ts
LEFT JOIN close_votes_per_tag cv ON cv.TagName = ts.TagName
ORDER BY ts.NumQuestions DESC
LIMIT 100;