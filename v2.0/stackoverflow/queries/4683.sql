-- {"query": "4683.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1310}
WITH RECURSIVE PostHierarchy AS (
    SELECT
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        1 AS Level
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL

    UNION ALL

    SELECT
        p.Id AS PostId,
        p.ParentId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        ph.Level + 1
    FROM Posts p
    JOIN PostHierarchy ph ON p.ParentId = ph.PostId
    WHERE p.PostTypeId = 2
),
AnswerScores AS (
    SELECT
        ParentId,
        SUM(CASE WHEN Score > 0 THEN Score ELSE 0 END) AS PositiveScoreSum,
        COUNT(Id) AS AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY ParentId
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersPosted,
        SUM(COALESCE(p.Score, 0)) AS TotalAcceptedAnswerScore,
        MAX(u.Reputation) AS MaxUserReputation,
        AVG(u.Views) AS AvgUserViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 1
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        (SELECT COUNT(*) FROM Posts WHERE PostTypeId = 1) AS TotalQuestions
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY t.TagName, t.Count
    HAVING t.Count > 100
),
ComplexPostData AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        COALESCE(a.PositiveScoreSum, 0) AS TotalAnswerPositiveScore,
        COALESCE(a.AnswerCount, 0) AS AnswerCount,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id
              AND c.CreationDate >= p.CreationDate + INTERVAL '1 day'
              AND c.Score < 0
        ) AS NegativeCommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) AS RankByType,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        p.PostTypeId,
        p.AnswerCount AS PostAnswerCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN AnswerScores a ON p.Id = a.ParentId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Score > 10 OR COALESCE(p.AnswerCount, 0) > 5
)
SELECT
    c.PostId,
    c.Title,
    c.PostTypeName,
    c.OwnerDisplayName,
    c.Score,
    c.TotalAnswerPositiveScore,
    c.AnswerCount,
    c.NegativeCommentCount,
    c.RankByType,
    c.PreviousPostScore,
    c.PostStatus,
    uc.QuestionCount,
    uc.TotalAnswersPosted,
    uc.TotalAcceptedAnswerScore,
    uc.MaxUserReputation,
    tp.TagName,
    tp.TagCount,
    tp.PostsWithTag,
    CASE
        WHEN c.Score > 100 THEN 'High'
        WHEN c.Score > 20 THEN 'Medium'
        ELSE 'Low'
    END AS ScoreCategory,
    UPPER(SUBSTRING(c.Title FROM 1 FOR 3)) AS TitlePrefix,
    COALESCE(
        (SELECT COUNT(DISTINCT v.UserId) FROM Votes v WHERE v.PostId = c.PostId AND v.VoteTypeId = 2),
        0
    ) AS UpVoteCount,
    CASE
        WHEN c.CreationDate < (DATE '2024-10-01') - INTERVAL '1 year' AND c.AnswerCount = 0 THEN 'Old and Unanswered'
        WHEN c.Score < 0 AND c.PostTypeName = 'Question' THEN 'Negatively Scored Question'
        ELSE 'Standard'
    END AS SpecialFlag,
    ph.Level AS HierarchyLevel,
    c.CreationDate
FROM ComplexPostData c
LEFT JOIN UserContributions uc ON c.OwnerDisplayName = uc.DisplayName
LEFT JOIN TagPopularity tp ON c.Title LIKE '%' || tp.TagName || '%'
LEFT JOIN PostHierarchy ph ON c.PostId = ph.PostId
WHERE c.Score > 0
  AND uc.AvgUserViews IS NOT NULL
  AND (tp.TagCount > 500 OR tp.TagName IS NULL)
GROUP BY
    c.PostId,
    c.Title,
    c.PostTypeName,
    c.OwnerDisplayName,
    c.Score,
    c.TotalAnswerPositiveScore,
    c.AnswerCount,
    c.NegativeCommentCount,
    c.RankByType,
    c.PreviousPostScore,
    c.PostStatus,
    uc.QuestionCount,
    uc.TotalAnswersPosted,
    uc.TotalAcceptedAnswerScore,
    uc.MaxUserReputation,
    uc.AvgUserViews,
    tp.TagName,
    tp.TagCount,
    tp.PostsWithTag,
    c.CreationDate,
    ph.Level
ORDER BY c.Score DESC, c.CreationDate DESC
LIMIT 100;