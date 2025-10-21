-- {"query": "49063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1835} 

WITH UserAggregatedStats AS (
    -- Aggregate user's overall activity: reputation, badge counts, and total comment contributions.
    -- Also sums favorite counts for questions they own.
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.Views AS UserProfileViews,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(COALESCE(P.FavoriteCount, 0)) FILTER (WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL) AS TotalFavoriteCountOnQuestionsOwned
    FROM Users AS U
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    GROUP BY U.Id, U.Reputation, U.Views, U.CreationDate, U.LastAccessDate
),
HighImpactPostsAndAnswers AS (
    -- Identify questions that are considered "high impact" based on score, views, and answers.
    -- Then link them to their accepted answers and the owners of both.
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerUserId,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.CreationDate AS QuestionCreationDate,
        A.Id AS AcceptedAnswerId,
        A.OwnerUserId AS AcceptedAnswerOwnerUserId,
        LENGTH(A.Body) AS AcceptedAnswerBodyLength,
        A.Score AS AcceptedAnswerScore,
        A.CreationDate AS AcceptedAnswerCreationDate
    FROM Posts AS Q
    JOIN Posts AS A ON Q.AcceptedAnswerId = A.Id
    WHERE Q.PostTypeId = 1 -- Must be a question
      AND A.PostTypeId = 2 -- Must be an answer
      AND Q.Score >= 20    -- Minimum score for the question
      AND Q.ViewCount >= 2000 -- Minimum view count for the question
      AND Q.AnswerCount >= 3 -- Minimum answers for the question
      AND Q.CreationDate BETWEEN '2021-01-01' AND '2023-12-31' -- Focus on recent questions
      AND Q.Tags LIKE '%<sql>%' OR Q.Tags LIKE '%<database>%' OR Q.Tags LIKE '%<performance>%' -- Focus on specific tag domains
),
UserEngagementOnHighImpact AS (
    -- Aggregate user's direct engagement with high-impact content, both as question owners and accepted answerers.
    SELECT
        COALESCE(H.QuestionOwnerUserId, H.AcceptedAnswerOwnerUserId) AS UserId,
        COUNT(DISTINCT H.QuestionId) AS HighImpactQuestionsInvolvedIn,
        SUM(H.QuestionScore) FILTER (WHERE H.QuestionOwnerUserId IS NOT NULL) AS TotalQuestionScoreAsOwner,
        SUM(H.QuestionViewCount) FILTER (WHERE H.QuestionOwnerUserId IS NOT NULL) AS TotalQuestionViewCountAsOwner,
        SUM(H.AcceptedAnswerScore) FILTER (WHERE H.AcceptedAnswerOwnerUserId IS NOT NULL) AS TotalAcceptedAnswerScore,
        AVG(H.AcceptedAnswerBodyLength) FILTER (WHERE H.AcceptedAnswerOwnerUserId IS NOT NULL) AS AvgAcceptedAnswerBodyLength,
        COUNT(H.AcceptedAnswerId) FILTER (WHERE H.AcceptedAnswerOwnerUserId IS NOT NULL) AS AcceptedAnswersCount
    FROM HighImpactPostsAndAnswers AS H
    GROUP BY COALESCE(H.QuestionOwnerUserId, H.AcceptedAnswerOwnerUserId)
),
UserPostEditActivity AS (
    -- Summarize significant edit activity for posts owned by the user.
    -- Focuses on body and tag edits/rollbacks.
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH.Id) AS TotalMajorEditsToOwnedPosts,
        MAX(PH.CreationDate) AS LastEditActivityDateForOwnedPosts
    FROM Posts AS P
    JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL
      AND PH.UserId = P.OwnerUserId -- Only count self-edits
      AND PH.PostHistoryTypeId IN (5, 6, 8, 9) -- Edit Body, Edit Tags, Rollback Body, Rollback Tags
      AND PH.CreationDate >= '2021-01-01' -- Recent edit activity
    GROUP BY P.OwnerUserId
)
-- Final result: Combine all user metrics into a single "Influence Score" for ranking.
SELECT
    UAS.UserId,
    U.DisplayName,
    UAS.Reputation,
    UAS.UserProfileViews,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    UAS.TotalCommentsMade,
    UAS.TotalFavoriteCountOnQuestionsOwned,
    COALESCE(UEHI.HighImpactQuestionsInvolvedIn, 0) AS HighImpactQuestionsInvolvedIn,
    COALESCE(UEHI.TotalQuestionScoreAsOwner, 0) AS TotalQuestionScoreAsOwner,
    COALESCE(UEHI.TotalQuestionViewCountAsOwner, 0) AS TotalQuestionViewCountAsOwner,
    COALESCE(UEHI.TotalAcceptedAnswerScore, 0) AS TotalAcceptedAnswerScore,
    COALESCE(UEHI.AvgAcceptedAnswerBodyLength, 0) AS AvgAcceptedAnswerBodyLength,
    COALESCE(UEHI.AcceptedAnswersCount, 0) AS AcceptedAnswersCount,
    COALESCE(UPEA.TotalMajorEditsToOwnedPosts, 0) AS TotalMajorEditsToOwnedPosts,
    UPEA.LastEditActivityDateForOwnedPosts,
    (
        -- Weighted sum of various metrics to produce an "Influence Score"
        (UAS.Reputation * 0.05) +
        (UAS.GoldBadges * 100) +
        (UAS.SilverBadges * 50) +
        (UAS.BronzeBadges * 10) +
        (COALESCE(UEHI.TotalQuestionScoreAsOwner, 0) * 0.2) +
        (COALESCE(UEHI.TotalAcceptedAnswerScore, 0) * 0.3) +
        (COALESCE(UEHI.AvgAcceptedAnswerBodyLength, 0) * 0.005) +
        (COALESCE(UAS.TotalFavoriteCountOnQuestionsOwned, 0) * 0.5) +
        (COALESCE(UPEA.TotalMajorEditsToOwnedPosts, 0) * 5) +
        (COALESCE(UEHI.HighImpactQuestionsInvolvedIn, 0) * 20) +
        (COALESCE(UAS.TotalCommentsMade, 0) * 0.1) +
        (COALESCE(UAS.UserProfileViews, 0) * 0.001)
    ) AS InfluenceScore
FROM Users AS U
LEFT JOIN UserAggregatedStats AS UAS ON U.Id = UAS.UserId
LEFT JOIN UserEngagementOnHighImpact AS UEHI ON U.Id = UEHI.UserId
LEFT JOIN UserPostEditActivity AS UPEA ON U.Id = UPEA.UserId
WHERE U.Reputation > 500 -- Filter out users with very low reputation
  AND U.LastAccessDate >= '2023-01-01' -- Ensure recent activity
ORDER BY InfluenceScore DESC NULLS LAST, UAS.Reputation DESC
LIMIT 50;
