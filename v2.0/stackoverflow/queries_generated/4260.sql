-- {"query": "4260.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1577} 

WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS PostCount,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(Score) AS AvgPostScore,
        MAX(CreationDate) AS LastPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserVoteSummary AS (
    SELECT
        UserId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS TotalUpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS TotalDownVotes,
        COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 END) AS AcceptedAnswers,
        SUM(CASE WHEN vt.Name = 'BountyStart' THEN 1 ELSE 0 END) AS BountyGivers
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Score AS QuestionScore,
        p.AnswerCount,
        p.CreationDate AS QuestionCreationDate,
        ROW_NUMBER() OVER(ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= DATE('now', '-1 year')
),
QuestionAnswers AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCountForQuestion,
        AVG(a.Score) AS AvgAnswerScoreForQuestion,
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer
    FROM Posts a
    JOIN Posts p ON a.ParentId = p.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.ParentId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COALESCE(upc.PostCount, 0) AS TotalPosts,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        COALESCE(upc.AvgPostScore, 0.0) AS AveragePostScore,
        COALESCE(uvs.TotalUpVotes, 0) AS VotesReceived,
        COALESCE(uvs.TotalDownVotes, 0) AS VotesGiven,
        COALESCE(uvs.AcceptedAnswers, 0) AS AcceptedAnswersCount,
        COALESCE(uvs.BountyGivers, 0) AS BountyAwards,
        COALESCE(rq.RowNum, 9999999) AS RecentQuestionRank,
        COALESCE(qa.AvgAnswerScoreForQuestion, 0.0) AS AvgScoreOfMyAnswersToThisQuestion,
        CASE WHEN u.Location LIKE '%USA%' THEN 'Domestic' WHEN u.Location LIKE '%Canada%' THEN 'North America' WHEN u.Location IS NULL THEN 'Unknown' ELSE 'International' END AS GeographicRegion,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND LOWER(u.WebsiteUrl) LIKE '%stackoverflow.com%' THEN 'StackOverflowRelated' WHEN u.WebsiteUrl IS NOT NULL THEN 'External' ELSE 'None' END AS WebsiteType,
        DATEDIFF(CURRENT_TIMESTAMP, u.LastAccessDate) AS DaysSinceLastAccess
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    LEFT JOIN UserVoteSummary uvs ON u.Id = uvs.UserId
    LEFT JOIN RecentQuestions rq ON u.Id = rq.OwnerUserId
    LEFT JOIN QuestionAnswers qa ON u.Id = qa.OwnerUserId AND rq.QuestionId = qa.QuestionId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.AveragePostScore,
    ue.VotesReceived,
    ue.VotesGiven,
    ue.AcceptedAnswersCount,
    ue.BountyAwards,
    ue.RecentQuestionRank,
    ue.AvgScoreOfMyAnswersToThisQuestion,
    ue.GeographicRegion,
    ue.WebsiteType,
    ue.DaysSinceLastAccess,
    COALESCE(b.Name, 'No Badge') AS HighestBadgeEarned,
    CASE
        WHEN ue.Reputation > 100000 THEN 'Expert'
        WHEN ue.Reputation > 10000 THEN 'Advanced'
        WHEN ue.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS ReputationLevel,
    CASE
        WHEN ue.TotalQuestions > 0 AND ue.TotalAnswers > 0 THEN CAST(ue.TotalAnswers AS REAL) / ue.TotalQuestions
        ELSE 0.0
    END AS AnswerToQuestionRatio,
    UPPER(SUBSTRING(ue.DisplayName, 1, 3)) AS DisplayNameInitial,
    CASE WHEN ue.DaysSinceLastAccess < 30 THEN 'Active' WHEN ue.DaysSinceLastAccess < 365 THEN 'Dormant' ELSE 'Inactive' END AS UserActivityStatus,
    (SELECT COUNT(*) FROM Badges b_inner WHERE b_inner.UserId = ue.UserId AND b_inner.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b_inner WHERE b_inner.UserId = ue.UserId AND b_inner.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b_inner WHERE b_inner.UserId = ue.UserId AND b_inner.Class = 3) AS BronzeBadges,
    CASE WHEN ue.TotalPosts > 0 AND ue.AveragePostScore > (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = ue.UserId) THEN 'Above Average' ELSE 'Below Average' END AS ScoreComparison,
    SUM(ue.TotalPosts) OVER (PARTITION BY ue.GeographicRegion) AS TotalPostsInRegion
FROM UserEngagement ue
LEFT JOIN (
    SELECT
        UserId,
        Name,
        ROW_NUMBER() OVER(PARTITION BY UserId ORDER BY Date DESC) as rn
    FROM Badges
) b ON ue.UserId = b.UserId AND b.rn = 1
WHERE ue.Reputation > 100 AND ue.TotalPosts > 5
ORDER BY ue.Reputation DESC, ue.DisplayName ASC
LIMIT 100;
