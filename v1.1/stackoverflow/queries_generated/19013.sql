-- {"query": "19013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2545} 

WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(SUM(P.FavoriteCount), 0) AS TotalPostFavorites,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        -- Calculate User specific average answer score directly
        COALESCE(AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score END) FILTER (WHERE P.PostTypeId = 2), 0) AS AvgUserAnswerScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
UserBadgeAchievements AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(DISTINCT B.Class) AS DistinctBadgeClasses,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
QuestionDetails AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId,
        Q.CreationDate AS QuestionCreationDate,
        Q.Score AS QuestionScore,
        Q.ViewCount AS QuestionViewCount,
        Q.AnswerCount AS QuestionAnswerCount,
        Q.FavoriteCount AS QuestionFavoriteCount,
        -- Correlated subquery: Check if this question has an accepted answer with a high score
        EXISTS (
            SELECT 1
            FROM Posts A
            WHERE A.Id = Q.AcceptedAnswerId AND A.Score >= 10
        ) AS HasHighScoreAcceptedAnswer,
        -- Another correlated subquery: Average score of answers to this question
        (
            SELECT COALESCE(AVG(A2.Score), 0)
            FROM Posts A2
            WHERE A2.ParentId = Q.Id AND A2.PostTypeId = 2
        ) AS AvgAnswerScoreForQuestion
    FROM Posts Q
    WHERE Q.PostTypeId = 1
),
AnswerDetails AS (
    SELECT
        A.Id AS AnswerId,
        A.ParentId AS QuestionId,
        A.OwnerUserId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        LENGTH(A.Body) - LENGTH(REPLACE(A.Body, '<pre>', '')) AS CodeBlockCount, -- Count <pre> tags
        -- Window function: Calculate the difference in score between current and previous answer by the same user
        COALESCE(A.Score - LAG(A.Score, 1, 0) OVER (PARTITION BY A.OwnerUserId ORDER BY A.CreationDate), 0) AS ScoreChangeFromPrevAnswer
    FROM Posts A
    WHERE A.PostTypeId = 2
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        MAX(PH.CreationDate) AS LastHistoryDate,
        COALESCE(
            MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Comment END),
            'N/A'
        ) AS LastCloseReasonComment
    FROM PostHistory PH
    GROUP BY PH.PostId
),
UserAggregatedPostHistory AS (
    SELECT
        P.OwnerUserId AS UserId,
        SUM(PHA_inner.TotalHistoryEntries) AS TotalHistoryEntries,
        SUM(PHA_inner.EditCount) AS EditCount,
        SUM(PHA_inner.CloseVoteCount) AS CloseVoteCount,
        MAX(PHA_inner.LastCloseReasonComment) FILTER (WHERE PHA_inner.LastCloseReasonComment != 'N/A') AS LastCloseReasonComment
    FROM Posts P
    JOIN PostHistoryAnalysis PHA_inner ON P.Id = PHA_inner.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserTopPosts AS (
    SELECT
        Q.OwnerUserId AS UserId,
        MAX(Q.QuestionScore) AS TopQuestionScore,
        MAX(Q.QuestionViewCount) AS TopQuestionViewCount,
        MAX(Q.QuestionAnswerCount) AS TopQuestionAnswerCount
    FROM QuestionDetails Q
    GROUP BY Q.OwnerUserId
),
UserTopAnswers AS (
    SELECT
        A.OwnerUserId AS UserId,
        MAX(A.AnswerScore) AS TopAnswerScore,
        MAX(A.CodeBlockCount) AS MaxAnswerCodeBlocks,
        MAX(A.ScoreChangeFromPrevAnswer) AS MaxAnswerScoreChange
    FROM AnswerDetails A
    GROUP BY A.OwnerUserId
),
GlobalMetrics AS (
    SELECT AVG(Score) AS GlobalAvgAnswerScore FROM Posts WHERE PostTypeId = 2 AND Score > 0
)
SELECT
    UCS.UserId,
    UCS.DisplayName,
    UCS.Reputation,
    UCS.TotalPosts,
    UCS.TotalQuestions,
    UCS.TotalAnswers,
    UCS.TotalCommentsMade,
    UBA.TotalBadges,
    UBA.GoldBadges,
    COALESCE(UTP.TopQuestionScore, 0) AS TopQuestionScore,
    COALESCE(UTP.TopQuestionViewCount, 0) AS TopQuestionViewCount,
    COALESCE(UTA.TopAnswerScore, 0) AS TopAnswerScore,
    COALESCE(UTA.MaxAnswerCodeBlocks, 0) AS MaxAnswerCodeBlocks,
    UCS.AvgUserAnswerScore,
    COALESCE(UTA.MaxAnswerScoreChange, 0) AS MaxAnswerScoreChange,
    -- Window function: Rank users by reputation within creation date quartiles
    NTILE(4) OVER (ORDER BY UCS.UserCreationDate) AS CreationDateQuartile,
    RANK() OVER (ORDER BY UCS.Reputation DESC, UCS.TotalPostScore DESC, UCS.TotalPostViews DESC) AS OverallReputationRank,
    COALESCE(UAPH.TotalHistoryEntries, 0) AS TotalHistoryEntriesForUserPosts,
    COALESCE(UAPH.EditCount, 0) AS EditCountForUserPosts,
    COALESCE(UAPH.CloseVoteCount, 0) AS CloseVoteCountForUserPosts,
    COALESCE(UAPH.LastCloseReasonComment, 'N/A') AS LastCloseReasonCommentForUserPosts,
    -- Complicated expression: User "Influence Factor"
    (
        CAST(UCS.Reputation AS numeric) * 0.1
        + CAST(COALESCE(UTP.TopQuestionScore, 0) AS numeric) * 0.7
        + CAST(COALESCE(UTA.TopAnswerScore, 0) AS numeric) * 0.8
        + CAST(COALESCE(UBA.GoldBadges, 0) AS numeric) * 10
        + (CASE WHEN UCS.AvgUserAnswerScore > GM.GlobalAvgAnswerScore THEN 100 ELSE 0 END)
        + (SELECT COUNT(DISTINCT PT.TagName) FROM Posts P_inner JOIN UNNEST(string_to_array(substring(P_inner.Tags, 2, length(P_inner.Tags)-2), '><')) AS PT(TagName) WHERE P_inner.OwnerUserId = UCS.UserId AND P_inner.PostTypeId = 1 AND P_inner.Tags IS NOT NULL) * 2
        + (SELECT COUNT(DISTINCT PL_inner.RelatedPostId) FROM Posts P_related JOIN PostLinks PL_inner ON P_related.Id = PL_inner.PostId WHERE P_related.OwnerUserId = UCS.UserId AND PL_inner.LinkTypeId = 1) * 3
    ) AS UserInfluenceFactor,
    -- String expression: Extracting initial reputation tier based on reputation
    CASE
        WHEN UCS.Reputation >= 10000 THEN 'Legend'
        WHEN UCS.Reputation >= 5000 THEN 'Veteran'
        WHEN UCS.Reputation >= 1000 THEN 'Experienced'
        WHEN UCS.Reputation >= 250 THEN 'Active'
        ELSE 'Novice'
    END AS ReputationTier,
    -- NULL logic & String expression: Check if DisplayName contains specific patterns
    UCS.DisplayName IS NOT NULL AND (UCS.DisplayName LIKE '%Admin%' OR UCS.DisplayName SIMILAR TO '%(Mod|Staff)%') AS IsModeratorLikeName,
    COALESCE(PLS.TotalPostsLinkingOut, 0) AS TotalPostsLinkingOut,
    COALESCE(PLS.TotalPostsMarkedAsDuplicate, 0) AS TotalPostsMarkedAsDuplicate
FROM UserContributionSummary UCS
LEFT JOIN UserBadgeAchievements UBA ON UCS.UserId = UBA.UserId
LEFT JOIN UserTopPosts UTP ON UCS.UserId = UTP.UserId
LEFT JOIN UserTopAnswers UTA ON UCS.UserId = UTA.UserId
LEFT JOIN UserAggregatedPostHistory UAPH ON UCS.UserId = UAPH.UserId
LEFT JOIN (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL.PostId) FILTER (WHERE PL.LinkTypeId = 1) AS TotalPostsLinkingOut,
        COUNT(DISTINCT PL.PostId) FILTER (WHERE PL.LinkTypeId = 3) AS TotalPostsMarkedAsDuplicate
    FROM Posts P
    JOIN PostLinks PL ON P.Id = PL.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
) AS PLS ON UCS.UserId = PLS.UserId
CROSS JOIN GlobalMetrics GM
WHERE
    UCS.Reputation >= 1000 -- Filter for somewhat active users
    AND UCS.TotalPosts > 5
    AND UCS.AvgUserAnswerScore > GM.GlobalAvgAnswerScore * 0.5
ORDER BY UserInfluenceFactor DESC, OverallReputationRank ASC
LIMIT 100;
