-- {"query": "5796.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 948} 
WITH
-- sample date range and active users for benchmarking
ActiveUsers AS (
    SELECT Id, Reputation, CreationDate, LastAccessDate
    FROM Users
    WHERE CreationDate >= '2018-01-01' AND LastAccessDate >= '2024-01-01'
),
-- recent posts with computed engagement
RecentPosts AS (
    SELECT p.Id,
           p.PostTypeId,
           p.OwnerUserId,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.AnswerCount,
           p.CommentCount,
           p.Tags,
           p.LastActivityDate,
           p.ParentId,
           p.AcceptedAnswerId,
           p.LastEditorUserId,
           p.LastEditDate,
           p.ContentLicense,
           CASE
               WHEN p.OwnerUserId IS NULL THEN 0
               ELSE 1
           END AS HasOwner
    FROM Posts p
    WHERE p.CreationDate >= DATEADD(year, -2, GETDATE())
),
-- top tags derived from tag snapshots
TagStats AS (
    SELECT t.TagName,
           t.Count,
           t.IsModeratorOnly,
           t.IsRequired
    FROM Tags t
),
-- correlated subquery: compute per-post recent related posts via PostLinks (duplicates/links)
PostRelations AS (
    SELECT pl.PostId,
           pl.RelatedPostId,
           pl.LinkTypeId,
           ll.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes ll ON pl.LinkTypeId = ll.Id
    WHERE pl.CreationDate >= DATEADD(year, -1, GETDATE())
),
-- windowed ranking: for each user, rank their posts by CreationDate and Score
UserPostRank AS (
    SELECT up.Id AS UserId,
           p.Id AS PostId,
           p.Title,
           p.Score,
           p.CreationDate,
           ROW_NUMBER() OVER (PARTITION BY up.Id ORDER BY p.CreationDate DESC, p.Score DESC) AS PostRank
    FROM ActiveUsers up
    JOIN Posts p ON p.OwnerUserId = up.Id
    WHERE p.CreationDate >= DATEADD(year, -2, GETDATE())
),
-- aggregate derived metrics with NULL handling and expressions
BenchMetrics AS (
    SELECT
        rp.Id AS PostId,
        rp.PostTypeId,
        rp.OwnerUserId,
        rp.Title,
        rp.CreationDate,
        rp.ViewCount,
        rp.Score,
        rp.AnswerCount,
        rp.CommentCount,
        rp.Tags,
        COALESCE(pv.Score, 0) AS PreviousScoreHint,
        CAST(NULLIF(rp.ContentLicense, '') AS varchar(30)) AS License,
        CASE WHEN rp.AcceptedAnswerId IS NULL THEN 0 ELSE 1 END AS HasAccepted
    FROM RecentPosts rp
    LEFT JOIN Posts pv ON pv.Id = rp.ParentId
),
-- complex predicate with nested expressions and NULL-safe logic
ComplexPredicate AS (
    SELECT *,
           CASE
               WHEN Score > 0 AND ViewCount > 100 THEN 'Hot'
               WHEN Coalesce(Score,0) = 0 AND CommentCount > 20 THEN 'Buzz'
               WHEN Tags IS NOT NULL AND Tags <> '' AND CHARINDEX('<', Tags) > 0 THEN 'Tagged'
               ELSE 'Moderate'
           END AS BenchmarkLabel,
           -- string expression: normalized title length and tag count
           LEN(Title) AS TitleLength,
           (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = BenchMetrics.PostId) AS LinkCount
    FROM BenchMetrics
),
-- final join to include user reputation and recent activity
Final AS (
    SELECT
        cb.PostId,
        cb.PostTypeId,
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.LastAccessDate,
        cb.Title,
        cb.ViewCount,
        cb.Score,
        cb.AnswerCount,
        cb.CommentCount,
        cb.Tags,
        cb.BenchmarkLabel,
        cl.Name AS CloseReasonName
    FROM ComplexPredicate cb
    LEFT JOIN Users u ON cb.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON ph.PostId = cb.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cl ON CAST(JSON_VALUE(ph.Text, '$.CloseReasonId') AS int) = cl.Id
)
SELECT
    *
FROM Final
ORDER BY BenchmarkLabel, Reputation DESC, CreationDate DESC
OPTION (RECOMPILE);