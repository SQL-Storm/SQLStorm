WITH RecentPosts AS (
    SELECT Id, PostTypeId, CreationDate, Score, ViewCount, AnswerCount, CommentCount, FavoriteCount, OwnerUserId, Tags
    FROM Posts
    WHERE CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '1 year'
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
    WHERE u.LastAccessDate >= CAST('2024-10-01' AS date) - INTERVAL '6 months'
    GROUP BY u.Id, u.DisplayName
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
    LEFT JOIN RecentPosts p ON p.Tags IS NOT NULL AND POSITION(CONCAT('<', t.TagName, '>') IN p.Tags) > 0
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
JOIN TagAnalysis ta ON EXISTS (
    SELECT 1
    FROM RecentPosts rp
    WHERE rp.OwnerUserId = tc.UserId
      AND rp.Tags IS NOT NULL
      AND POSITION(CONCAT('<', ta.TagName, '>') IN rp.Tags) > 0
)
ORDER BY tc.TotalQuestionScore + tc.TotalAnswerScore DESC
LIMIT 50;