-- {"query": "43052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 696} 

WITH RecentPosts AS (
    SELECT Id, PostTypeId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount, OwnerUserId
    FROM Posts
    WHERE CreationDate >= CURRENT_DATE - INTERVAL '1 year'
),
TopContributors AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN RecentPosts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE u.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 5
        OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 10
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsTagged,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersTagged,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore
    FROM Tags t
    LEFT JOIN RecentPosts p ON POSITION(t.TagName IN p.Tags) > 0
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 10
)
SELECT 
    tc.DisplayName,
    tc.QuestionsAsked,
    tc.AnswersProvided,
    tc.TotalQuestionScore,
    tc.TotalAnswerScore,
    tc.EditCount,
    ta.TagName,
    ta.QuestionsTagged,
    ta.AnswersTagged,
    ta.AvgQuestionScore,
    ta.AvgAnswerScore
FROM TopContributors tc
JOIN TagAnalysis ta ON tc.UserId IN (
    SELECT DISTINCT OwnerUserId 
    FROM RecentPosts 
    WHERE POSITION(ta.TagName IN Tags) > 0
)
ORDER BY tc.TotalQuestionScore + tc.TotalAnswerScore DESC
LIMIT 50;
