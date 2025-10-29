-- {"query": "4464.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1318} 
WITH LatestPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
UserEngagement AS (
    SELECT
        lp.OwnerUserId,
        COUNT(DISTINCT lp.PostId) AS TotalQuestions,
        SUM(lp.PostScore) AS TotalScoreGained,
        AVG(lp.PostViewCount) AS AvgViewsPerQuestion,
        SUM(CASE WHEN lp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS ClosedQuestions,
        COUNT(DISTINCT c.Id) AS TotalComments
    FROM LatestPosts lp
    LEFT JOIN Comments c ON lp.PostId = c.PostId
    GROUP BY lp.OwnerUserId
),
HighReputationUsers AS (
    SELECT
        Id
    FROM Users
    WHERE Reputation > 50000
),
PopularTags AS (
    SELECT
        t.TagName,
        SUM(t.Count) AS TotalTagCount,
        COUNT(DISTINCT lp.PostId) AS PostsWithTag,
        AVG(lp.PostScore) AS AvgScoreForTag
    FROM Tags t
    JOIN LatestPosts lp ON ',' || lp.Tags || ',' LIKE '%,' || t.TagName || ',%'
    WHERE t.IsModeratorOnly = FALSE
    GROUP BY t.TagName
    ORDER BY TotalTagCount DESC
    LIMIT 10
),
QuestionsWithManyAnswers AS (
    SELECT
        lp.PostId,
        lp.Title,
        lp.OwnerUserId,
        lp.AnswerCount,
        lp.PostCreationDate
    FROM LatestPosts lp
    WHERE lp.AnswerCount > 10
),
AggregatedData AS (
    SELECT
        ug.OwnerUserId,
        ug.TotalQuestions,
        ug.TotalScoreGained,
        ug.AvgViewsPerQuestion,
        ug.ClosedQuestions,
        ug.TotalComments,
        hr.Id AS IsHighReputation
    FROM UserEngagement ug
    LEFT JOIN HighReputationUsers hr ON ug.OwnerUserId = hr.Id
)
SELECT
    COALESCE(a.OwnerUserId, p.OwnerUserId) AS FinalUserId,
    COALESCE(a.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(a.TotalScoreGained, 0) AS UserTotalScore,
    COALESCE(a.AvgViewsPerQuestion, 0.0) AS UserAvgViews,
    COALESCE(a.ClosedQuestions, 0) AS UserClosedQuestions,
    COALESCE(a.TotalComments, 0) AS UserTotalComments,
    CASE WHEN a.IsHighReputation IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsUserHighReputation,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(a.OwnerUserId, p.OwnerUserId) AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(a.OwnerUserId, p.OwnerUserId) AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(a.OwnerUserId, p.OwnerUserId) AND b.Class = 3) AS BronzeBadges,
    (
        SELECT STRING_AGG(pt.TagName, '; ')
        FROM PopularTags pt
        JOIN LatestPosts lp ON ',' || lp.Tags || ',' LIKE '%,' || pt.TagName || '%'
        WHERE lp.OwnerUserId = COALESCE(a.OwnerUserId, p.OwnerUserId)
    ) AS TopTagsForUser,
    (SELECT SUM(AnswerCount) FROM QuestionsWithManyAnswers q WHERE q.OwnerUserId = COALESCE(a.OwnerUserId, p.OwnerUserId)) AS UserQuestionsWithManyAnswers,
    CASE
        WHEN COALESCE(a.TotalQuestions, 0) > 0 THEN
            CAST(COALESCE(a.TotalScoreGained, 0) AS REAL) / a.TotalQuestions
        ELSE 0.0
    END AS ScorePerQuestion,
    CASE
        WHEN COALESCE(a.TotalQuestions, 0) > 0 THEN
            CAST(COALESCE(a.TotalComments, 0) AS REAL) / a.TotalQuestions
        ELSE 0.0
    END AS CommentsPerQuestion,
    (SELECT MAX(PostCreationDate) FROM LatestPosts WHERE OwnerUserId = COALESCE(a.OwnerUserId, p.OwnerUserId)) AS LastQuestionDate,
    (SELECT MIN(PostCreationDate) FROM LatestPosts WHERE OwnerUserId = COALESCE(a.OwnerUserId, p.OwnerUserId)) AS FirstQuestionDate
FROM AggregatedData a
FULL OUTER JOIN LatestPosts p ON a.OwnerUserId = p.OwnerUserId
WHERE a.OwnerUserId IS NOT NULL OR p.OwnerUserId IS NOT NULL
GROUP BY COALESCE(a.OwnerUserId, p.OwnerUserId), a.TotalQuestions, a.TotalScoreGained, a.AvgViewsPerQuestion, a.ClosedQuestions, a.TotalComments, a.IsHighReputation, p.OwnerUserId
HAVING COUNT(p.PostId) > 0 OR COUNT(a.OwnerUserId) > 0
ORDER BY FinalUserId;