-- {"query": "50044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 828} 
WITH UserAnswerStats AS (
    -- Calculate statistics for each user's answers
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        AVG(p.Score) AS AverageAnswerScore,
        SUM(p.CommentCount) AS TotalAnswerComments,
        MAX(p.CreationDate) AS LastAnswerDate,
        MIN(p.CreationDate) AS FirstAnswerDate,
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswers
    FROM Posts p
    LEFT JOIN Votes v ON p.AcceptedAnswerId = v.PostId
    WHERE p.PostTypeId = 2 -- Answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 10
),
UserQuestionStats AS (
    -- Calculate statistics for each user's questions
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalQuestions,
        AVG(Score) AS AverageQuestionScore,
        SUM(ViewCount) AS TotalQuestionViews,
        SUM(FavoriteCount) AS TotalQuestionFavorites
    FROM Posts
    WHERE PostTypeId = 1 -- Questions
      AND OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
UserBadgeRanks AS (
    -- Rank users based on the number of gold badges they've earned
    SELECT
        UserId,
        COUNT(Id) AS GoldBadges,
        DENSE_RANK() OVER (ORDER BY COUNT(Id) DESC) as GoldBadgeRank
    FROM Badges
    WHERE Class = 1 -- Gold badges
    GROUP BY UserId
)
-- Final query: Combine user stats to find elite users who are both good answerers and question askers
-- and rank them based on their editing history and gold badge count.
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    uas.TotalAnswers,
    uas.AverageAnswerScore,
    uas.TotalAcceptedAnswers,
    CAST(uas.TotalAcceptedAnswers AS REAL) / uas.TotalAnswers AS AcceptanceRate,
    uqs.TotalQuestions,
    uqs.AverageQuestionScore,
    uqs.TotalQuestionViews,
    ubr.GoldBadges,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS TotalEdits,
    (uas.LastAnswerDate - uas.FirstAnswerDate) AS AnsweringLifespan
FROM Users u
JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
JOIN UserQuestionStats uqs ON u.Id = uqs.OwnerUserId
JOIN UserBadgeRanks ubr ON u.Id = ubr.UserId
WHERE u.Reputation > (SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY Reputation) FROM Users) -- Top 5% reputation
  AND u.UpVotes > u.DownVotes
  AND ubr.GoldBadgeRank <= 100
  AND EXISTS (
    -- Ensure the user has answered at least one question with a very high score
    SELECT 1
    FROM Posts p_sub
    WHERE p_sub.OwnerUserId = u.Id
      AND p_sub.PostTypeId = 2
      AND p_sub.Score > 500
  )
ORDER BY
    u.Reputation DESC,
    ubr.GoldBadges DESC,
    AcceptanceRate DESC
LIMIT 100;