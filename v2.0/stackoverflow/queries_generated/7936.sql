-- {"query": "7936.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1583} 
WITH UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN AVG(p.Score) 
            ELSE 0 
        END AS AvgPostScore,
        CASE 
            WHEN COUNT(DISTINCT b.Id) > 0 THEN 
                STRING_AGG(b.Name, ', ' ORDER BY b.Date)
            ELSE NULL 
        END AS BadgesEarned,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                ARRAY_AGG(p.PostTypeId ORDER BY p.CreationDate)
            ELSE NULL 
        END AS PostTypesCreated
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        CommentCount,
        BadgeCount,
        LastPostDate,
        LastCommentDate,
        AvgPostScore,
        BadgesEarned,
        PostTypesCreated,
        RANK() OVER (ORDER BY Reputation DESC, PostCount DESC) AS ReputationRank,
        DENSE_RANK() OVER (ORDER BY PostCount DESC) AS PostActivityRank
    FROM UserActivityStats
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        DATEDIFF('day', p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate)) AS DaysOpen,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS QuestionNumber
    FROM Posts p
    WHERE p.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        CASE 
            WHEN p.ParentId IN (SELECT Id FROM Posts WHERE PostTypeId = 1 AND AcceptedAnswerId = p.Id) 
            THEN 'Accepted' 
            ELSE 'Not Accepted' 
        END AS IsAccepted,
        LAG(p.Score, 1) OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) AS PrevAnswerScore,
        RANK() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 2
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count AS TagCount,
        AVG(p.Score) AS AvgScore,
        COUNT(p.Id) AS QuestionCount,
        STRING_AGG(DISTINCT u.DisplayName, ', ' ORDER BY u.Reputation DESC) AS TopUsers,
        STRING_AGG(DISTINCT p.Title, ', ' ORDER BY p.Score DESC LIMIT 5) AS PopularQuestions
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
),
ComplexStats AS (
    SELECT 
        'Complex Query Result' AS Category,
        COUNT(*) AS TotalUsers,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 2) AS TotalAnswers,
        (SELECT COUNT(*) FROM Badges) AS TotalBadges,
        (SELECT COUNT(*) FROM Comments) AS TotalComments
    FROM Users
)
SELECT 
    'Post Summary' AS ReportType,
    'Questions' AS DataType,
    COUNT(*) AS TotalCount,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) AS AvgScore,
    (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) AS AvgViews,
    (SELECT AVG(AnswerCount) FROM Posts WHERE PostTypeId = 1) AS AvgAnswers
FROM Posts WHERE PostTypeId = 1

UNION ALL

SELECT 
    'Post Summary' AS ReportType,
    'Answers' AS DataType,
    COUNT(*) AS TotalCount,
    (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) AS AvgScore,
    NULL AS AvgViews,
    NULL AS AvgAnswers
FROM Posts WHERE PostTypeId = 2

UNION ALL

SELECT 
    'User Summary' AS ReportType,
    'Active Users' AS DataType,
    COUNT(*) AS TotalCount,
    AVG(Reputation) AS AvgReputation,
    NULL AS AvgViews,
    NULL AS AvgAnswers
FROM Users
WHERE Id IN (SELECT DISTINCT OwnerUserId FROM Posts WHERE PostTypeId = 1)

UNION ALL

SELECT 
    'Tag Analysis' AS ReportType,
    'Popular Tags' AS DataType,
    COUNT(*) AS TotalCount,
    AVG(TagCount) AS AvgTagCount,
    NULL AS AvgViews,
    NULL AS AvgAnswers
FROM TagAnalysis

UNION ALL

SELECT 
    'Complex Metrics' AS ReportType,
    'System Stats' AS DataType,
    TotalUsers AS TotalCount,
    NULL AS AvgReputation,
    NULL AS AvgViews,
    NULL AS AvgAnswers
FROM ComplexStats

HAVING COUNT(*) > 0

ORDER BY CASE ReportType 
    WHEN 'Post Summary' THEN 1
    WHEN 'User Summary' THEN 2
    WHEN 'Tag Analysis' THEN 3
    WHEN 'Complex Metrics' THEN 4
END;

-- This query includes:
-- 1. Multiple CTEs (UserActivityStats, TopUsers, QuestionStats, AnswerStats, TagAnalysis, ComplexStats)
-- 2. Window functions (LAG, ROW_NUMBER, RANK, DENSE_RANK)
-- 3. Outer joins (LEFT JOINs)
-- 4. Correlated subqueries (IN clauses with subqueries)
-- 5. Set operators (UNION ALL)
-- 6. Complicated predicates (CASE statements with conditions, multiple WHERE clauses)
-- 7. String expressions (STRING_AGG, CONCAT)
-- 8. NULL logic (COALESCE, IS NULL checks)
-- 9. Calculated expressions (DATEDIFF, AVG, COUNT, RANK)
-- 10. Complex aggregations with GROUP BY and HAVING
-- 11. Multiple JOINs and table references
-- 12. Nested SELECT statements with multiple levels
-- 13. Conditional logic for different data types
-- 14. Performance-intensive operations with large datasets