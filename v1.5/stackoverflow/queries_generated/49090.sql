-- {"query": "49090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1603} 

WITH UserQuestionStats AS (
    -- Aggregates core statistics for questions asked by each user within the last 5 years
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT q.Id) AS TotalQuestionsAsked,
        SUM(q.ViewCount) AS TotalQuestionViews,
        SUM(COALESCE(q.FavoriteCount, 0)) AS TotalQuestionFavorites,
        MAX(q.CreationDate) AS LastQuestionActivityDate
    FROM Users AS u
    INNER JOIN Posts AS q ON u.Id = q.OwnerUserId
    WHERE
        q.PostTypeId = 1 -- Only questions
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '5 year'
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        COUNT(DISTINCT q.Id) >= 10 -- Minimum 10 questions to qualify
        AND u.Reputation >= 1000 -- Minimum reputation
),
QuestionAnswerPerformance AS (
    -- Calculates the average score of answers for each question, filtering for questions with well-received answers
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        AVG(a.Score * 1.0) AS AverageAnswerScore,
        COUNT(a.Id) AS NumberOfAnswers,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Posts AS q
    INNER JOIN Posts AS a ON q.Id = a.ParentId
    WHERE
        q.PostTypeId = 1 -- Question
        AND a.PostTypeId = 2 -- Answer
        AND a.CreationDate >= CURRENT_DATE - INTERVAL '5 year'
    GROUP BY
        q.Id, q.OwnerUserId
    HAVING
        AVG(a.Score * 1.0) >= 7.0 -- Average answer score of at least 7
        AND COUNT(a.Id) >= 3 -- At least 3 answers per question
),
QuestionTagPopularity AS (
    -- Determines the cumulative popularity of tags associated with qualifying questions
    SELECT
        q.Id AS QuestionId,
        SUM(t.Count) AS TotalQuestionTagPopularity,
        COUNT(DISTINCT t.Id) AS DistinctTagCount
    FROM Posts AS q
    CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2), '><')) AS tag_name_unnested
    INNER JOIN Tags AS t ON t.TagName = tag_name_unnested
    WHERE
        q.PostTypeId = 1
        AND q.Tags IS NOT NULL
        AND LENGTH(q.Tags) > 2 -- Ensures valid tags string
    GROUP BY
        q.Id
    HAVING
        SUM(t.Count) > 5000 -- Tags collectively popular
),
UserEngagementMetrics AS (
    -- Gathers diverse user engagement metrics (badges, comments, votes given)
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT b.Id) AS TotalBadgesReceived,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesGiven
    FROM Users AS u
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId
    WHERE
        u.LastAccessDate >= CURRENT_DATE - INTERVAL '5 year'
    GROUP BY
        u.Id
)
SELECT
    uqs.UserId,
    uqs.DisplayName,
    uqs.Reputation,
    uqs.TotalQuestionsAsked,
    uqs.TotalQuestionViews,
    uqs.TotalQuestionFavorites,
    uqs.LastQuestionActivityDate,
    AVG(qap.AverageAnswerScore) AS AverageOfAnswerScoresAcrossQuestions,
    AVG(qap.NumberOfAnswers) AS AverageAnswersPerQuestion,
    SUM(qtp.TotalQuestionTagPopularity) AS CumulativeTagPopularityForUserQuestions,
    COUNT(DISTINCT qap.QuestionId) AS QuestionsWithHighPerformingAnswers,
    uem.TotalBadgesReceived,
    uem.GoldBadges,
    uem.TotalCommentsMade,
    uem.TotalUpvotesGiven,
    uem.TotalDownvotesGiven,
    -- A composite score evaluating user's contribution, engagement, and content quality
    (
        uqs.Reputation * 0.05 +
        uqs.TotalQuestionsAsked * 0.5 +
        uqs.TotalQuestionViews * 0.0005 +
        uqs.TotalQuestionFavorites * 0.2 +
        AVG(qap.AverageAnswerScore) * 1.5 +
        SUM(qtp.TotalQuestionTagPopularity) * 0.00001 +
        uem.TotalBadgesReceived * 0.1 +
        uem.GoldBadges * 1.0 +
        uem.TotalCommentsMade * 0.05 +
        uem.TotalUpvotesGiven * 0.01
    ) AS UserCompositeScore,
    RANK() OVER (
        ORDER BY
            (uqs.Reputation * 0.05 + AVG(qap.AverageAnswerScore) * 1.5 + SUM(qtp.TotalQuestionTagPopularity) * 0.00001 + uem.GoldBadges * 1.0) DESC,
            uqs.LastQuestionActivityDate DESC
    ) AS UserRankByImpact
FROM UserQuestionStats AS uqs
INNER JOIN QuestionAnswerPerformance AS qap ON uqs.UserId = qap.OwnerUserId
INNER JOIN QuestionTagPopularity AS qtp ON qap.QuestionId = qtp.QuestionId
LEFT JOIN UserEngagementMetrics AS uem ON uqs.UserId = uem.UserId
GROUP BY
    uqs.UserId, uqs.DisplayName, uqs.Reputation, uqs.CreationDate,
    uqs.TotalQuestionsAsked, uqs.TotalQuestionViews, uqs.TotalQuestionFavorites,
    uqs.LastQuestionActivityDate, uem.TotalBadgesReceived, uem.GoldBadges,
    uem.TotalCommentsMade, uem.TotalUpvotesGiven, uem.TotalDownvotesGiven
HAVING
    COUNT(DISTINCT qap.QuestionId) >= 5 -- User must have at least 5 questions with high-performing answers
    AND AVG(qap.AverageAnswerScore) >= 8.0 -- Overall average answer score for their questions must be high
ORDER BY
    UserCompositeScore DESC, UserRankByImpact ASC
LIMIT 50;
