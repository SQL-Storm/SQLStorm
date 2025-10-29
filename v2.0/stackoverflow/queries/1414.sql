-- {"query": "1414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2643} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(P.Score), 0) AS TotalPostsScore,
        COALESCE(SUM(C.Score), 0) AS TotalCommentsScore,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MIN(P.CreationDate) AS FirstPostDate,
        DATE_PART('day', U.LastAccessDate - U.CreationDate) AS DaysSinceCreation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location
),
PostMetrics AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.AcceptedAnswerId,
        P.ParentId,
        -- Extract tags into an array for easier querying
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') AS TagArray,
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount, -- UpMod
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount, -- DownMod
        -- Correlated subquery: Average score of answers to this specific question
        (SELECT AVG(CAST(Ans.Score AS DECIMAL))
         FROM Posts AS Ans
         WHERE Ans.ParentId = P.Id AND Ans.PostTypeId = 2) AS AvgAnswerScoreForQuestion
    FROM Posts AS P
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community user/deleted users
),
PostHistoryDetails AS (
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditEvents, -- Edit Title, Body, Tags
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseEvents, -- Post Closed
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEvents, -- Post Reopened
        COUNT(DISTINCT PH.UserId) AS DistinctEditors, -- How many unique users edited this post
        MAX(PH.CreationDate) AS LastEditDate
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
CommentSentiment AS (
    SELECT
        C.PostId,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%helpful%' OR LOWER(C.Text) LIKE '%great%' THEN 1 ELSE 0 END) AS PositiveCommentCount,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%issue%' OR LOWER(C.Text) LIKE '%problem%' THEN 1 ELSE 0 END) AS NegativeCommentCount,
        COUNT(C.Id) AS TotalCommentsOnPost
    FROM Comments AS C
    GROUP BY C.PostId
),
BadgeAwards AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges AS B
    GROUP BY B.UserId
),
UserQuestionPerformance AS (
    SELECT
        PM.OwnerUserId AS UserId,
        COUNT(PM.PostId) AS QuestionsAsked,
        SUM(PM.ViewCount) AS TotalQuestionViews,
        SUM(PM.FavoriteCount) AS TotalQuestionFavorites,
        SUM(PM.UpVoteCount) AS TotalQuestionUpVotes,
        SUM(PM.DownVoteCount) AS TotalQuestionDownVotes,
        SUM(CASE WHEN PM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        AVG(PM.AvgAnswerScoreForQuestion) AS AvgAnswerScoreOnQuestions,
        SUM(PHD.EditEvents) AS TotalQuestionEditEvents,
        SUM(PHD.CloseEvents) AS TotalQuestionCloseEvents,
        SUM(PHD.ReopenEvents) AS TotalQuestionReopenEvents,
        SUM(CS.PositiveCommentCount) AS TotalPositiveCommentsOnQuestions,
        SUM(CS.NegativeCommentCount) AS TotalNegativeCommentsOnQuestions,
        SUM(CASE WHEN 'sql' = ANY(PM.TagArray) THEN 1 ELSE 0 END) AS SQLQuestionsAsked,
        SUM(CASE WHEN 'python' = ANY(PM.TagArray) THEN 1 ELSE 0 END) AS PythonQuestionsAsked
    FROM PostMetrics AS PM
    LEFT JOIN PostHistoryDetails AS PHD ON PM.PostId = PHD.PostId
    LEFT JOIN CommentSentiment AS CS ON PM.PostId = CS.PostId
    WHERE PM.PostTypeId = 1
    GROUP BY PM.OwnerUserId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.Location,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalCommentsMade,
    UAS.TotalPostsScore,
    UAS.TotalCommentsScore,
    UAS.LastPostActivityDate,
    UAS.DaysSinceCreation,

    -- User Question Performance Metrics
    COALESCE(UQP.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UQP.TotalQuestionViews, 0) AS TotalQuestionViews,
    COALESCE(UQP.TotalQuestionFavorites, 0) AS TotalQuestionFavorites,
    COALESCE(UQP.TotalQuestionUpVotes, 0) AS TotalQuestionUpVotes,
    COALESCE(UQP.TotalQuestionDownVotes, 0) AS TotalQuestionDownVotes,
    COALESCE(UQP.QuestionsWithAcceptedAnswer, 0) AS QuestionsWithAcceptedAnswer,
    COALESCE(UQP.AvgAnswerScoreOnQuestions, 0.0) AS AvgAnswerScoreOnQuestions,
    COALESCE(UQP.TotalQuestionEditEvents, 0) AS TotalQuestionEditEvents,
    COALESCE(UQP.TotalQuestionCloseEvents, 0) AS TotalQuestionCloseEvents,
    COALESCE(UQP.TotalQuestionReopenEvents, 0) AS TotalQuestionReopenEvents,
    COALESCE(UQP.TotalPositiveCommentsOnQuestions, 0) AS TotalPositiveCommentsOnQuestions,
    COALESCE(UQP.TotalNegativeCommentsOnQuestions, 0) AS TotalNegativeCommentsOnQuestions,
    COALESCE(UQP.SQLQuestionsAsked, 0) AS SQLQuestionsAsked,
    COALESCE(UQP.PythonQuestionsAsked, 0) AS PythonQuestionsAsked,

    -- Badge Summary
    COALESCE(BA.GoldBadges, 0) AS GoldBadges,
    COALESCE(BA.SilverBadges, 0) AS SilverBadges,
    COALESCE(BA.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(BA.TotalBadges, 0) AS TotalBadges,
    BA.LastBadgeDate,

    -- Derived Metrics & Calculations
    CAST(COALESCE(UQP.QuestionsWithAcceptedAnswer, 0) AS DECIMAL) * 100 / NULLIF(COALESCE(UQP.QuestionsAsked, 0), 0) AS QuestionAcceptanceRate,
    CAST(COALESCE(UQP.TotalQuestionUpVotes, 0) AS DECIMAL) / NULLIF(COALESCE(UQP.TotalQuestionDownVotes, 0), 0) AS QuestionUpToDownVoteRatio,
    CAST(COALESCE(UQP.TotalQuestionEditEvents, 0) AS DECIMAL) / NULLIF(COALESCE(UQP.QuestionsAsked, 0), 0) AS AvgEditsPerQuestion,
    COALESCE(UQP.TotalPositiveCommentsOnQuestions, 0) - COALESCE(UQP.TotalNegativeCommentsOnQuestions, 0) AS NetQuestionCommentSentiment,

    -- Window Functions: Rank users by reputation within their location, and overall
    RANK() OVER (PARTITION BY UAS.Location ORDER BY UAS.Reputation DESC, UAS.TotalPostsScore DESC) AS RankByReputationInLocation,
    ROW_NUMBER() OVER (ORDER BY UAS.TotalPostsScore DESC, UAS.Reputation DESC, UAS.UserCreationDate ASC) AS OverallActivityRank,

    -- NULL Logic and Conditional Expressions
    CASE
        WHEN UAS.LastAccessDate IS NULL THEN 'Never Logged In'
        WHEN UAS.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days') THEN 'Highly Active'
        WHEN UAS.LastAccessDate >= (cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year') THEN 'Moderately Active'
        ELSE 'Infrequently Active'
    END AS UserActivityStatus,
    CASE
        WHEN UAS.Reputation >= 100000 THEN 'Elite'
        WHEN UAS.Reputation >= 25000 THEN 'Veteran'
        WHEN UAS.Reputation >= 5000 THEN 'Expert'
        WHEN UAS.Reputation >= 1000 THEN 'Journeyman'
        WHEN UAS.Reputation >= 200 THEN 'Apprentice'
        ELSE 'Newbie'
    END AS ReputationTier,
    (UAS.TotalPostsScore + UAS.TotalCommentsScore + (COALESCE(BA.TotalBadges, 0) * 10)) AS WeightedActivityScore -- Complicated calculation
FROM UserActivitySummary AS UAS
LEFT JOIN UserQuestionPerformance AS UQP ON UAS.UserId = UQP.UserId
LEFT JOIN BadgeAwards AS BA ON UAS.UserId = BA.UserId
WHERE
    UAS.Reputation > 500 -- Focus on more established users
    AND UAS.TotalPosts > 0 -- Ensure the user has posted something
    AND UAS.Location IS NOT NULL -- Exclude users with unspecified location for location-based ranking
    AND (COALESCE(UQP.TotalQuestionViews, 0) > 100 OR COALESCE(BA.TotalBadges, 0) > 5) -- Filter for popular questioners or badge earners
ORDER BY
    WeightedActivityScore DESC,
    OverallActivityRank ASC
LIMIT 1000;