-- {"query": "4290.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1025} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        pht.Name AS EditTypeName,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(u.LastAccessDate) AS LastLoginDate,
        AVG(CASE WHEN p.Id IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Views > 1000 -- Filter for relatively active users
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
HighScoringAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS HighScoringAnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2 -- It's an answer
      AND p.Score > 10 -- High score threshold
    GROUP BY p.ParentId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPostsCreated,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalCommentsMade,
    ua.LastLoginDate,
    ua.AvgPostScore,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    COALESCE(hsa.HighScoringAnswerCount, 0) AS NumHighScoringAnswers,
    CASE
        WHEN rpe.PostId IS NOT NULL THEN 'Yes'
        ELSE 'No'
    END AS HasRecentEdits,
    LOWER(SUBSTRING(ua.DisplayName FROM 1 FOR 3)) AS NamePrefix,
    CASE
        WHEN ua.Reputation BETWEEN 100 AND 1000 THEN 'Novice'
        WHEN ua.Reputation BETWEEN 1001 AND 10000 THEN 'Intermediate'
        WHEN ua.Reputation > 10000 THEN 'Expert'
        ELSE 'Beginner'
    END AS ReputationLevel,
    (ua.GoldBadges * 1000 + ua.SilverBadges * 100 + ua.BronzeBadges * 10) AS BadgeScore,
    p.Title AS SampleQuestionTitle,
    p.CreationDate AS SampleQuestionDate,
    p.Score AS SampleQuestionScore,
    p.AnswerCount AS SampleQuestionAnswerCount,
    COALESCE(p.FavoriteCount, 0) AS QuestionFavorites
FROM UserActivity ua
LEFT JOIN HighScoringAnswers hsa ON ua.UserId = hsa.QuestionId
LEFT JOIN RankedPostEdits rpe ON ua.UserId = rpe.UserId AND rpe.rn = 1 -- Get the most recent edit for each user
LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId AND p.PostTypeId = 1 -- Sample a question from the user
WHERE ua.Reputation > 500 AND ua.AnswersGiven > 10
ORDER BY ua.Reputation DESC, ua.TotalPostsCreated DESC
LIMIT 100;
