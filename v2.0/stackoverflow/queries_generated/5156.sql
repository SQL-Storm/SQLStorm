-- {"query": "5156.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 692} 
WITH
-- recent top-scoring questions by tag, with windowed ranking per tag
TopQuestions AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.OwnerDisplayName,
        ROW_NUMBER() OVER (
            PARTITION BY t.TagName
            ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
        ) AS rn
    FROM Posts p
    CROSS APPLY (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    ) AS t
    WHERE p.PostTypeId = 1 -- Questions
      AND p.ClosedDate IS NULL
),
-- aggregate per tag: average score, total views, and active user activity
TagStats AS (
    SELECT
        t.TagName,
        AVG(t.Score) AS AvgScore,
        SUM(t.ViewCount) AS TotalViews,
        COUNT(DISTINCT t.OwnerUserId) AS DistinctOwners,
        MIN(t.CreationDate) AS FirstQuestionDate,
        MAX(t.CreationDate) AS LastQuestionDate
    FROM TopQuestions t
    GROUP BY t.TagName
),
-- find correlated hot questions: those with recent activity and high score
HotQuestions AS (
    SELECT
        tq.PostId,
        tq.Title,
        tq.Tags,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        tq.OwnerUserId,
        tq.OwnerDisplayName,
        tq.rn,
        ts.AvgScore,
        ts.TotalViews,
        ts.DistinctOwners,
        ts.FirstQuestionDate
    FROM TopQuestions tq
    JOIN TagStats ts
      ON ts.TagName = (SELECT TagName FROM (VALUES (regexp_replace(tq.Tags, '[<>]', '', 'g'))) AS x(TagName) LIMIT 1)
    WHERE tq.rn <= 3 -- top 3 per tag
),
-- compute a composite performance metric with NULL-safe arithmetic
BenchResults AS (
    SELECT
        h.PostId,
        h.Title,
        h.Tags,
        h.CreationDate,
        h.Score,
        h.ViewCount,
        h.OwnerUserId,
        h.OwnerDisplayName,
        h.AvgScore,
        h.TotalViews,
        h.DistinctOwners,
        h.FirstQuestionDate,
        (COALESCE(h.Score,0) * 1.5
         + COALESCE(h.ViewCount,0) * 0.8
         + COALESCE(h.AvgScore,0) * 2.0
         + COALESCE(h.TotalViews,0) * 0.01) AS PerformanceScore
    FROM HotQuestions h
)
SELECT
    br.PostId,
    br.Title,
    br.Tags,
    br.CreationDate,
    br.Score,
    br.ViewCount,
    br.OwnerUserId,
    br.OwnerDisplayName,
    br.AvgScore,
    br.TotalViews,
    br.DistinctOwners,
    br.FirstQuestionDate,
    br.PerformanceScore
FROM BenchResults br
ORDER BY br.PerformanceScore DESC, br.CreationDate DESC
LIMIT 100;