-- {"query": "5652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 918} 
WITH
-- A rich dataset combining posts, users, votes, and tags for benchmarking
RecentActivePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.CommentCount,
        p.AnswerCount,
        p.FavoriteCount
    FROM Posts p
    WHERE p.CreationDate >= NOW() - INTERVAL '30 days'
),
-- Correlated data: last editor and a detailed edit history impact
PostEditImpact AS (
    SELECT
        rap.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate END) AS LastBodyEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate END) AS LastTagsEditDate
    FROM RecentActivePosts rap
    LEFT JOIN PostHistory ph ON ph.PostId = rap.PostId
    GROUP BY rap.PostId
),
-- Windowed metrics: cumulative unique commenters per post
CommentersPerPost AS (
    SELECT
        c.PostId,
        COUNT(DISTINCT c.UserId) OVER (PARTITION BY c.PostId ORDER BY c.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeCommenters
    FROM Comments c
    WHERE c.PostId IN (SELECT PostId FROM RecentActivePosts)
),
-- Examples of complex predicates and string expressions
TagScore AS (
    SELECT
        t.TagName,
        t.Count,
        CASE
            WHEN t.Count > 1000 THEN 'hot'
            WHEN t.Count BETWEEN 100 AND 1000 THEN 'warm'
            ELSE 'cold'
        END AS TagTemperature,
        CONCAT('tag/', LOWER(t.TagName)) AS TagPath
    FROM Tags t
    WHERE t.TagName IS NOT NULL
),
-- Set operation: union a quick derived tag summary with a more expensive tag summary
TagSummary AS (
    SELECT TagName FROM Tags WHERE IsModeratorOnly = 0
    UNION
    SELECT 'all-tags' AS TagName
),
-- Outer join scenario: ensure all recent posts appear with optional metrics from edits
PostWithMetrics AS (
    SELECT
        rap.PostId,
        rap.Title,
        rap.Tags,
        rap.CreationDate,
        rap.LastActivityDate,
        rap.Score,
        rap.ViewCount,
        COALESCE(pe.LastBodyEditDate, rap.CreationDate) AS LastBodyEditDate,
        COALESCE(pe.LastTitleEditDate, rap.CreationDate) AS LastTitleEditDate,
        COALESCE(pe.LastTagsEditDate, rap.CreationDate) AS LastTagsEditDate,
        ccp.CumulativeCommenters,
        tp.Name AS PostTypeName
    FROM RecentActivePosts rap
    LEFT JOIN PostEditImpact pe ON pe.PostId = rap.PostId
    LEFT JOIN CommentersPerPost ccp ON ccp.PostId = rap.PostId
    LEFT JOIN PostTypes tp ON tp.Id = rap.PostTypeId
),
-- Final composite with advanced calculations and NULL handling
FinalBenchmark AS (
    SELECT
        pwp.PostId,
        pwp.PostTypeName,
        pwp.Title,
        pwp.Tags,
        pwp.CreationDate,
        pwp.LastActivityDate,
        pwp.Score,
        pwp.ViewCount,
        pwp.LastBodyEditDate,
        pwp.LastTitleEditDate,
        pwp.LastTagsEditDate,
        pwp.CumulativeCommenters,
        CASE
            WHEN pwp.Score >= 50 THEN TRUE
            ELSE FALSE
        END AS HighImpact,
        CASE
            WHEN pwp.ViewCount / NULLIF(pwp.Score,0) > 20 THEN 'heavy-traffic'
            ELSE 'moderate'
        END AS TrafficCategory,
        CASE
            WHEN pwp.Tags ~ '\\<python\\>' THEN 'contains-python'
            ELSE 'no-python'
        END AS TagPresence
    FROM PostWithMetrics pwp
)
SELECT
    *
FROM FinalBenchmark
ORDER BY LastActivityDate DESC
LIMIT 100;