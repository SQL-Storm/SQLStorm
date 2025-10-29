WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGivenBySelf,
        U.DownVotes AS TotalDownVotesGivenBySelf,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsPosted,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersPosted,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsOwned,
        COALESCE(SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END), 0) AS QuestionsWithAcceptedAnswers,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN P.ViewCount ELSE 0 END), 0) AS TotalQuestionViewsOnOwned,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreEarnedOnOwned,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMadeBySelf,
        CAST(COALESCE(SUM(P.Score), 0) AS numeric) / NULLIF(COUNT(DISTINCT P.Id), 0) AS AvgPostScorePerOwnedPost,
        CAST(COALESCE(COUNT(DISTINCT C.Id), 0) AS numeric) / NULLIF(COUNT(DISTINCT P.Id), 0) AS CommentToPostRatio
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostHistoricalAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.LastActivityDate,
        P.Score,
        P.ViewCount,
        P.FavoriteCount,
        P.CommentCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        P.Tags,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.Title,
        EXTRACT(EPOCH FROM (P.LastActivityDate - P.CreationDate)) / 3600.0 AS HoursUntilLastActivity,
        EXISTS (
            SELECT 1
            FROM PostHistory PH
            WHERE PH.PostId = P.Id
              AND PH.PostHistoryTypeId IN (4,5,6)
              AND PH.UserId IS NOT NULL
              AND PH.UserId != P.OwnerUserId
              AND PH.CreationDate > P.CreationDate
        ) AS WasEditedByOtherUser,
        (SELECT COUNT(DISTINCT PH_inner.UserId)
         FROM PostHistory PH_inner
         WHERE PH_inner.PostId = P.Id
           AND PH_inner.PostHistoryTypeId IN (4,5,6)
           AND PH_inner.UserId IS NOT NULL
           AND PH_inner.UserId != P.OwnerUserId) AS DistinctOtherEditorsCount,
        (P.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned,
        EXTRACT(EPOCH FROM (P.CreationDate - LAG(P.LastActivityDate, 1, P.CreationDate)
            OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate))) / 86400.0 AS DaysSincePreviousPostActivity
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
),
UserBadgeMetrics AS (
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(B.Id) AS TotalBadges,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
PostCloseReasons AS (
    SELECT
        PH.PostId,
        MAX(PH.CreationDate) AS LastClosedDate,
        (SELECT CR.Name FROM CloseReasonTypes CR WHERE CR.Id = CAST(PH_inner.Comment AS SMALLINT) LIMIT 1) AS CloseReasonName
    FROM PostHistory PH
    JOIN PostHistory PH_inner ON PH.Id = PH_inner.Id AND PH_inner.PostHistoryTypeId = 10
    WHERE PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId, PH_inner.Comment
),
TopUserQuestionDetails AS (
    SELECT
        PHA.PostId AS QuestionId,
        PHA.OwnerUserId AS QuestionOwnerId,
        PHA.Title AS QuestionTitle,
        PHA.PostCreationDate AS QuestionCreationDate,
        PHA.Score AS QuestionScore,
        PHA.ViewCount AS QuestionViewCount,
        PHA.FavoriteCount AS QuestionFavoriteCount,
        PHA.AnswerCount AS QuestionAnswerCount,
        PHA.CommentCount AS QuestionCommentCount,
        PHA.Tags AS QuestionTags,
        PHA.ClosedDate AS QuestionClosedDate,
        PCR.LastClosedDate AS QuestionLastClosedDate,
        PCR.CloseReasonName AS QuestionCloseReason,
        PHA.HoursUntilLastActivity,
        PHA.WasEditedByOtherUser,
        PHA.DistinctOtherEditorsCount,
        PHA.IsCommunityOwned,
        (SELECT A.Id FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerId,
        (SELECT A.Score FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerScore,
        (SELECT A.OwnerUserId FROM Posts A WHERE A.ParentId = PHA.PostId ORDER BY A.Score DESC, A.CreationDate ASC LIMIT 1) AS TopAnswerOwnerUserId,
        EXTRACT(EPOCH FROM (COALESCE(PHA.LastEditDate, PHA.PostCreationDate) - PHA.PostCreationDate)) / 3600.0 AS HoursToLastEdit,
        RANK() OVER (PARTITION BY PHA.OwnerUserId ORDER BY PHA.Score DESC, PHA.PostCreationDate DESC) AS QuestionScoreRankByUser
    FROM PostHistoricalAnalysis PHA
    LEFT JOIN PostCloseReasons PCR ON PHA.PostId = PCR.PostId
    WHERE PHA.PostTypeId = 1
),
UserTopTags AS (
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(tag) AS TagName,
        COUNT(*) AS QuestionCountWithTag,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(*) DESC, TRIM(tag) ASC) AS rn
    FROM Posts P,
         LATERAL (
           SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR CASE WHEN P.Tags IS NULL THEN 0 ELSE LENGTH(P.Tags) - 2 END), '><')) AS tag
         ) t
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL
    GROUP BY P.OwnerUserId, TRIM(tag)
)
SELECT
    UES.UserId,
    UES.DisplayName AS UserDisplayName,
    UES.Reputation,
    UES.UserCreationDate,
    UES.LastAccessDate,
    EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS timestamp) - UES.LastAccessDate)) AS DaysSinceLastAccess,
    UES.TotalUpVotesGivenBySelf,
    UES.TotalDownVotesGivenBySelf,
    UES.QuestionsPosted,
    UES.AnswersPosted,
    UES.TotalPostsOwned,
    UES.QuestionsWithAcceptedAnswers,
    UES.TotalQuestionViewsOnOwned,
    UES.TotalPostScoreEarnedOnOwned,
    UES.TotalCommentsMadeBySelf,
    UES.AvgPostScorePerOwnedPost,
    UES.CommentToPostRatio,
    UBM.GoldBadges,
    UBM.SilverBadges,
    UBM.BronzeBadges,
    UBM.TotalBadges,
    UBM.LastBadgeAwardDate,
    (SELECT AVG(PHA2.DaysSincePreviousPostActivity)
     FROM PostHistoricalAnalysis PHA2
     WHERE PHA2.OwnerUserId = UES.UserId AND PHA2.PostTypeId IN (1,2)
     GROUP BY PHA2.OwnerUserId) AS AvgDaysBetweenPosts,
    TQ.QuestionId,
    TQ.QuestionTitle,
    TQ.QuestionCreationDate,
    TQ.QuestionScore,
    TQ.QuestionViewCount,
    TQ.QuestionFavoriteCount,
    TQ.QuestionAnswerCount,
    TQ.QuestionCommentCount,
    TQ.QuestionTags,
    TQ.QuestionLastClosedDate,
    TQ.QuestionCloseReason,
    TQ.HoursUntilLastActivity,
    TQ.WasEditedByOtherUser,
    TQ.DistinctOtherEditorsCount,
    TQ.IsCommunityOwned,
    TQ.TopAnswerId,
    TQ.TopAnswerScore,
    TQ.TopAnswerOwnerUserId,
    TQ.HoursToLastEdit,
    TQ.QuestionScoreRankByUser,
    RANK() OVER (ORDER BY UES.Reputation DESC, UES.UserId ASC) AS UserReputationRank,
    CAST(UES.AnswersPosted AS numeric) / NULLIF(UES.TotalPostsOwned, 0) AS AnswerToTotalPostRatio,
    COALESCE(
        CASE WHEN U_main.Location IS NOT NULL THEN SPLIT_PART(U_main.Location, ',', 1) ELSE NULL END,
        'Unknown Location'
    ) AS PrimaryLocationGuess,
    CASE WHEN U_main.WebsiteUrl IS NOT NULL AND LENGTH(TRIM(U_main.WebsiteUrl)) > 0 THEN TRUE ELSE FALSE END AS HasWebsiteProfile,
    TMPT.TagName AS MostPopularTagBySelf,
    TMPT.QuestionCountWithTag AS MostPopularTagQuestionCountBySelf,
    EXISTS (
        SELECT 1
        FROM PostLinks PL
        WHERE PL.PostId = TQ.QuestionId
          AND PL.LinkTypeId = 3
    ) AS TopQuestionHasDuplicateLinks,
    (SELECT
        SUM(CASE WHEN LENGTH(P_body.Body) > 1500 THEN 1 ELSE 0 END) +
        SUM(CASE WHEN LOWER(P_body.Body) LIKE '%<code>%</code>%' THEN 1 ELSE 0 END)
     FROM Posts P_body WHERE P_body.OwnerUserId = UES.UserId AND P_body.PostTypeId = 1) AS ComplexQuestionsCountOwned,
    (UES.Reputation * 0.4) + (UES.TotalPostScoreEarnedOnOwned * 0.25) + (COALESCE(UBM.TotalBadges,0) * 0.2) + (UES.QuestionsPosted * 0.1) + (UES.AnswersPosted * 0.05) AS UserWeightedScore
FROM UserEngagementSummary UES
LEFT JOIN UserBadgeMetrics UBM ON UES.UserId = UBM.UserId
LEFT JOIN TopUserQuestionDetails TQ ON UES.UserId = TQ.QuestionOwnerId AND TQ.QuestionScoreRankByUser = 1
LEFT JOIN Users U_main ON UES.UserId = U_main.Id
LEFT JOIN UserTopTags TMPT ON UES.UserId = TMPT.UserId AND TMPT.rn = 1
WHERE UES.Reputation > 500
  AND UES.TotalPostsOwned > 10
ORDER BY UserWeightedScore DESC, UES.UserId ASC
LIMIT 1000;