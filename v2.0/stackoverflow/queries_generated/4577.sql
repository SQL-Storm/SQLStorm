-- {"query": "4577.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1666} 

WITH RankedAnswers AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as rn_score,
        COUNT(c.Id) OVER(PARTITION BY a.ParentId) AS AnswerCommentCount,
        CASE WHEN a.Id = q.AcceptedAnswerId THEN 1 ELSE 0 END AS IsAccepted,
        LEAD(a.Score, 1, -1) OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS NextBestScore
    FROM Posts a
    JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    WHERE a.PostTypeId = 2 -- It's an answer
    GROUP BY a.Id, a.ParentId, a.OwnerUserId, a.Score, a.CreationDate, q.AcceptedAnswerId
),
UserAnswerStats AS (
    SELECT
        ra.OwnerUserId,
        COUNT(DISTINCT ra.AnswerId) AS TotalAnswersGiven,
        SUM(ra.Score) AS TotalAnswerScore,
        AVG(CAST(ra.Score AS DECIMAL(10, 2))) AS AverageAnswerScore,
        COUNT(CASE WHEN ra.IsAccepted = 1 THEN 1 ELSE NULL END) AS AcceptedAnswersCount,
        SUM(CASE WHEN ra.IsAccepted = 1 THEN ra.Score ELSE 0 END) AS ScoreOfAcceptedAnswers
    FROM RankedAnswers ra
    WHERE ra.OwnerUserId IS NOT NULL
    GROUP BY ra.OwnerUserId
),
QuestionEngagement AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.CreationDate AS QuestionCreationDate,
        q.ClosedDate,
        COUNT(DISTINCT ra.AnswerId) AS TotalAnswers,
        SUM(CASE WHEN ra.rn_score = 1 THEN 1 ELSE 0 END) AS IsBestAnswerPresent, -- Indicates if the highest scored answer is ranked
        SUM(CASE WHEN ra.IsAccepted = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM Posts q
    LEFT JOIN RankedAnswers ra ON q.Id = ra.QuestionId
    WHERE q.PostTypeId = 1 -- It's a question
    GROUP BY q.Id, q.OwnerUserId, q.Score, q.ViewCount, q.CommentCount, q.FavoriteCount, q.CreationDate, q.ClosedDate
),
UserQuestionStats AS (
    SELECT
        qe.QuestionOwnerUserId,
        COUNT(DISTINCT qe.QuestionId) AS TotalQuestionsAsked,
        SUM(qe.QuestionScore) AS TotalQuestionScore,
        AVG(CAST(qe.QuestionScore AS DECIMAL(10, 2))) AS AverageQuestionScore,
        SUM(qe.TotalAnswers) AS TotalAnswersReceived,
        SUM(qe.AcceptedAnswerCount) AS TotalAcceptedAnswersReceived,
        COUNT(CASE WHEN qe.ClosedDate IS NOT NULL THEN 1 ELSE NULL END) AS ClosedQuestionsCount
    FROM QuestionEngagement qe
    WHERE qe.QuestionOwnerUserId IS NOT NULL
    GROUP BY qe.QuestionOwnerUserId
)
SELECT
    COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AS UserId,
    COALESCE(u.DisplayName, 'Unknown User') AS DisplayName,
    COALESCE(uas.TotalAnswersGiven, 0) AS TotalAnswersGiven,
    COALESCE(uas.TotalAnswerScore, 0) AS TotalAnswerScore,
    COALESCE(uas.AverageAnswerScore, 0.0) AS AverageAnswerScore,
    COALESCE(uas.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(uas.ScoreOfAcceptedAnswers, 0) AS ScoreOfAcceptedAnswers,
    COALESCE(uqs.TotalQuestionsAsked, 0) AS TotalQuestionsAsked,
    COALESCE(uqs.TotalQuestionScore, 0) AS TotalQuestionScore,
    COALESCE(uqs.AverageQuestionScore, 0.0) AS AverageQuestionScore,
    COALESCE(uqs.TotalAnswersReceived, 0) AS TotalAnswersReceived,
    COALESCE(uqs.TotalAcceptedAnswersReceived, 0) AS TotalAcceptedAnswersReceived,
    COALESCE(uqs.ClosedQuestionsCount, 0) AS ClosedQuestionsCount,
    CASE WHEN u.Reputation > 10000 THEN 'High Reputation'
         WHEN u.Reputation > 1000 THEN 'Medium Reputation'
         ELSE 'Low Reputation'
    END AS ReputationTier,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate AS UserLastAccessDate,
    u.Views AS UserTotalViews,
    LENGTH(u.AboutMe) AS AboutMeLength,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AND b.Class = 3) AS BronzeBadges,
    CASE WHEN EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AND p.ClosedDate IS NOT NULL) THEN 'HasClosedPosts' ELSE 'NoClosedPosts' END AS PostClosureStatus,
    REPLACE(UPPER(COALESCE(u.Location, 'Unknown Location')), ' ', '_') AS FormattedLocation,
    (SELECT TOP 1 Name FROM VoteTypes vt WHERE vt.Id = 2) AS UpVoteTypeName, -- Simple example of selecting a value and aliasing it
    CAST(DATE_PART('year', u.CreationDate) AS VARCHAR) || '-' || CAST(DATE_PART('month', u.CreationDate) AS VARCHAR) AS UserCreationMonth,
    CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    (SELECT COUNT(DISTINCT ph.PostId) FROM PostHistory ph WHERE ph.UserId = COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) AND ph.PostHistoryTypeId IN (4, 5, 6)) AS PostEditsMade
FROM UserAnswerStats uas
FULL OUTER JOIN UserQuestionStats uqs ON uas.OwnerUserId = uqs.QuestionOwnerUserId
LEFT JOIN Users u ON COALESCE(uas.OwnerUserId, uqs.QuestionOwnerUserId) = u.Id
WHERE u.Id IS NOT NULL OR uas.OwnerUserId IS NOT NULL OR uqs.QuestionOwnerUserId IS NOT NULL
ORDER BY UserCreationMonth DESC, ReputationTier, UserTotalViews;
