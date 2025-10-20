-- {"query": "50042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1142} 

WITH UserAnswerStats AS (
    -- Step 1: Aggregate answer statistics for each user
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS NumberOfAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AverageAnswerScore,
        SUM(p.CommentCount) AS TotalAnswerCommentCount
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answers
    AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserQuestionStats AS (
    -- Step 2: Aggregate question statistics for each user, including engagement on their questions
    SELECT
        q.OwnerUserId,
        COUNT(q.Id) AS NumberOfQuestions,
        SUM(q.ViewCount) AS TotalQuestionViews,
        SUM(q.AnswerCount) AS TotalAnswersOnQuestions,
        AVG(q.FavoriteCount) AS AverageFavoriteCount,
        -- Find the user's most upvoted question
        MAX(q.Score) AS MaxQuestionScore
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Questions
    AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
),
UserBadgeStats AS (
    -- Step 3: Count Gold, Silver, and Bronze badges for each user
    SELECT
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserActivityRanking AS (
    -- Step 4: Combine all stats and calculate a composite 'ActivityScore'
    -- Also, rank users within their location based on reputation
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        uas.NumberOfAnswers,
        uas.TotalAnswerScore,
        uqs.NumberOfQuestions,
        uqs.TotalQuestionViews,
        ubs.GoldBadges,
        ubs.SilverBadges,
        -- Calculate a weighted ActivityScore
        (COALESCE(uas.TotalAnswerScore, 0) * 0.4) +
        (COALESCE(uqs.TotalQuestionViews, 0) * 0.1) +
        (u.UpVotes * 0.2) - (u.DownVotes * 0.3) +
        (COALESCE(ubs.GoldBadges, 0) * 100) +
        (COALESCE(ubs.SilverBadges, 0) * 25) AS ActivityScore,
        -- Correlated subquery to find the date of the user's first-ever vote
        (SELECT MIN(v.CreationDate) FROM Votes v WHERE v.UserId = u.Id) AS FirstVoteDate,
        -- Window function to rank users by reputation within their geographical location
        DENSE_RANK() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) as LocationReputationRank
    FROM Users u
    LEFT JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
    LEFT JOIN UserQuestionStats uqs ON u.Id = uqs.OwnerUserId
    LEFT JOIN UserBadgeStats ubs ON u.Id = ubs.UserId
    WHERE u.Reputation > 1000
    AND u.Location IS NOT NULL AND u.Location != ''
)
-- Final Selection: Find the top 200 most active users who are also ranked highly in their location
-- and have answered questions with a "difficult" tag like 'c++' or 'java'.
SELECT
    ar.DisplayName,
    ar.Reputation,
    ar.Location,
    ar.ActivityScore,
    ar.LocationReputationRank,
    ar.NumberOfAnswers,
    ar.TotalAnswerScore,
    ar.NumberOfQuestions,
    ar.TotalQuestionViews,
    ar.GoldBadges,
    ar.FirstVoteDate
FROM UserActivityRanking ar
-- Join back to Posts to check if the user has answered a question with a specific 'difficult' tag
WHERE EXISTS (
    SELECT 1
    FROM Posts p_ans
    JOIN Posts p_ques ON p_ans.ParentId = p_ques.Id
    WHERE p_ans.OwnerUserId = ar.UserId
    AND p_ans.PostTypeId = 2 -- Answer
    AND p_ques.PostTypeId = 1 -- Question
    AND (p_ques.Tags LIKE '%<c++>%' OR p_ques.Tags LIKE '%<java>' OR p_ques.Tags LIKE '%<python>%')
)
AND ar.LocationReputationRank <= 5 -- Only include users who are in the top 5 for their location
ORDER BY ar.ActivityScore DESC, ar.Reputation DESC
LIMIT 200;
