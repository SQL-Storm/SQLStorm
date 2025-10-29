-- {"query": "4387.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1449} 

WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-30 days')
),
HighReputationAnswers AS (
    SELECT
        ans.ParentId AS QuestionId,
        ans.Id AS AnswerId,
        ans.OwnerUserId,
        ans.CreationDate AS AnswerCreationDate,
        ans.Score AS AnswerScore,
        ansUser.DisplayName AS AnswererDisplayName,
        ansUser.Reputation AS AnswererReputation,
        ROW_NUMBER() OVER (PARTITION BY ans.ParentId ORDER BY ans.Score DESC, ans.CreationDate ASC) AS answer_rn
    FROM Posts ans
    JOIN Users ansUser ON ans.OwnerUserId = ansUser.Id
    WHERE ans.PostTypeId = 2
      AND ansUser.Reputation >= 1000
),
QuestionStats AS (
    SELECT
        q.QuestionId,
        q.QuestionTitle,
        q.OwnerDisplayName,
        q.OwnerReputation,
        q.QuestionScore,
        q.AnswerCount,
        q.CommentCount,
        COALESCE(ha.AnswerId, -1) AS BestAnswerId,
        COALESCE(ha.AnswererDisplayName, 'No High Rep Answer') AS BestAnswerer,
        COALESCE(ha.AnswererReputation, 0) AS BestAnswererReputation,
        (q.QuestionScore + q.AnswerCount * 5 - q.CommentCount * 2) AS EngagementMetric
    FROM RecentQuestions q
    LEFT JOIN HighReputationAnswers ha ON q.QuestionId = ha.QuestionId AND ha.answer_rn = 1
    WHERE q.rn <= 50 -- Limiting to the 50 most recent questions
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IN (SELECT OwnerUserId FROM RecentQuestions)
       OR u.Id IN (SELECT OwnerUserId FROM HighReputationAnswers)
    GROUP BY u.Id, u.DisplayName
),
AllPostsAndComments AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate FROM Posts p
    UNION ALL
    SELECT c.Id, NULL AS PostTypeId, c.UserId AS OwnerUserId, c.CreationDate FROM Comments c
),
RecentUserActivity AS (
    SELECT
        UserId,
        COUNT(*) AS ActivityCount,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS RecentQuestions,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS RecentAnswers
    FROM AllPostsAndComments
    WHERE CreationDate >= DATE('now', '-7 days')
      AND UserId IS NOT NULL
    GROUP BY UserId
)
SELECT
    qs.QuestionTitle,
    qs.OwnerDisplayName,
    qs.OwnerReputation,
    qs.QuestionScore,
    qs.AnswerCount,
    qs.CommentCount,
    qs.EngagementMetric,
    qs.BestAnswerer,
    qs.BestAnswererReputation,
    ua.PostsCount AS TotalUserPosts,
    ua.AvgPostScore AS AvgUserPostScore,
    rua.ActivityCount AS RecentUserActivityCount,
    CASE
        WHEN qs.OwnerReputation > 10000 AND qs.QuestionScore > 50 THEN 'Highly Engaged Expert'
        WHEN qs.OwnerReputation > 1000 AND qs.AnswerCount > 5 THEN 'Experienced Contributor'
        WHEN qs.QuestionScore < 0 THEN 'Potentially Problematic'
        WHEN qs.AnswerCount = 0 AND qs.QuestionScore > 10 THEN 'Good Question, No Answers Yet'
        ELSE 'Standard Question'
    END AS QuestionCategorization,
    SUBSTRING(qs.QuestionTitle FROM 1 FOR 50) AS ShortTitle,
    DATE_PART('year', qs.QuestionCreationDate) AS QuestionYear,
    'Post Data:' || qs.QuestionTitle || ' by ' || qs.OwnerDisplayName AS ConcatenatedInfo,
    CASE WHEN qs.BestAnswererReputation > qs.OwnerReputation THEN 'Answerer Rep Higher' ELSE 'Owner Rep Higher or Equal' END AS ReputationComparison
FROM QuestionStats qs
LEFT JOIN UserActivity ua ON qs.OwnerUserId = ua.UserId
LEFT JOIN RecentUserActivity rua ON qs.OwnerUserId = rua.UserId
WHERE ua.ActivityCount > 10 -- Users with substantial activity
   OR ua.AvgPostScore > 5   -- Users with high average post scores
UNION
SELECT
    '---' AS QuestionTitle,
    '---' AS OwnerDisplayName,
    0 AS OwnerReputation,
    0 AS QuestionScore,
    0 AS AnswerCount,
    0 AS CommentCount,
    0 AS EngagementMetric,
    '---' AS BestAnswerer,
    0 AS BestAnswererReputation,
    0 AS TotalUserPosts,
    0.0 AS AvgUserPostScore,
    0 AS RecentUserActivityCount,
    'Summary Row' AS QuestionCategorization,
    '---' AS ShortTitle,
    0 AS QuestionYear,
    '---' AS ConcatenatedInfo,
    '---' AS ReputationComparison
ORDER BY EngagementMetric DESC
LIMIT 10;
