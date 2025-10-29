-- {"query": "1792.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3378} 

WITH UserCoreActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Location,
        U.AboutMe,
        U.WebsiteUrl,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsOwned,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreOwned,
        SUM(COALESCE(P.CommentCount, 0)) AS TotalCommentsOnOwnedPosts,
        COUNT(DISTINCT C.Id) AS TotalCommentsMadeByOwner,
        SUM(CASE WHEN PV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesReceivedOnPosts,
        SUM(CASE WHEN PV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesReceivedOnPosts,
        SUM(CASE WHEN UV.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN UV.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN UV.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoriteVotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes PV ON P.Id = PV.PostId AND PV.VoteTypeId IN (2, 3)
    LEFT JOIN Votes UV ON U.Id = UV.UserId AND UV.VoteTypeId IN (2, 3, 5)
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.AboutMe, U.WebsiteUrl
),
PostEditAnalysis AS (
    SELECT
        PH.PostId,
        P.OwnerUserId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS EditDate,
        PH.PostHistoryTypeId,
        PHT.Name AS PostHistoryTypeName,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS EditRankDesc,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.UserId ORDER BY PH.CreationDate ASC) AS UserEditRankAsc,
        (PH.UserId = P.OwnerUserId) AS IsOwnerEdit,
        EXTRACT(EPOCH FROM (PH.CreationDate - P.CreationDate)) / 3600 AS HoursToEdit
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    INNER JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8)
),
QuestionAnswerEngagement AS (
    SELECT
        Q.Id AS QuestionId,
        Q.OwnerUserId AS QuestionOwnerId,
        Q.CreationDate AS QuestionCreationDate,
        Q.ViewCount AS QuestionViewCount,
        Q.Score AS QuestionScore,
        A.Id AS AnswerId,
        A.OwnerUserId AS AnswerOwnerId,
        A.CreationDate AS AnswerCreationDate,
        A.Score AS AnswerScore,
        COALESCE(A.CommentCount, 0) AS AnswerCommentCount,
        EXTRACT(EPOCH FROM (A.CreationDate - LAG(A.CreationDate, 1, Q.CreationDate) OVER (PARTITION BY Q.Id ORDER BY A.CreationDate))) / 60 AS MinsBetweenAnswers,
        SUM(COALESCE(A.Score, 0)) OVER (PARTITION BY Q.Id ORDER BY A.CreationDate) AS CumulativeAnswerScore,
        RANK() OVER (PARTITION BY Q.Id ORDER BY A.Score DESC, A.CreationDate ASC) AS AnswerScoreRank,
        (A.Id = Q.AcceptedAnswerId) AS IsAcceptedAnswer
    FROM Posts Q
    INNER JOIN Posts A ON Q.Id = A.ParentId AND A.PostTypeId = 2
    WHERE Q.PostTypeId = 1 AND Q.ViewCount > 50 AND COALESCE(Q.AnswerCount, 0) > 0
),
AggregatedUserMetrics AS (
    SELECT
        UCA.UserId,
        UCA.DisplayName,
        UCA.Reputation,
        UCA.UserCreationDate,
        UCA.LastAccessDate,
        UCA.Location,
        UCA.AboutMe,
        UCA.WebsiteUrl,
        UCA.TotalPostsOwned,
        UCA.TotalQuestionsOwned,
        UCA.TotalAnswersOwned,
        UCA.TotalPostViewsOwned,
        UCA.TotalPostScoreOwned,
        UCA.TotalCommentsOnOwnedPosts,
        UCA.TotalCommentsMadeByOwner,
        UCA.TotalUpVotesReceivedOnPosts,
        UCA.TotalDownVotesReceivedOnPosts,
        UCA.TotalUpVotesGiven,
        UCA.TotalDownVotesGiven,
        UCA.TotalFavoriteVotesGiven,
        COALESCE(B.TotalBadges, 0) AS TotalBadges,
        COALESCE(B.GoldBadges, 0) AS GoldBadges,
        COALESCE(B.SilverBadges, 0) AS SilverBadges,
        COALESCE(B.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(B.BadgesPerDayActive, 0) AS BadgesPerDayActive,
        EXISTS (
            SELECT 1 FROM Posts P_inner WHERE P_inner.AcceptedAnswerId IS NOT NULL AND P_inner.OwnerUserId = UCA.UserId
        ) AS HasEverAcceptedAnswer,
        EXISTS (
            SELECT 1 FROM PostEditAnalysis PEA_inner WHERE PEA_inner.EditorUserId = UCA.UserId AND PEA_inner.OwnerUserId != UCA.UserId
        ) AS EditsOtherUsersPosts,
        NTILE(10) OVER (ORDER BY UCA.Reputation DESC) AS ReputationDecile,
        COUNT(DISTINCT CASE WHEN PEA.IsOwnerEdit THEN PEA.PostId END) AS SelfEditedPostsCount,
        CASE
            WHEN UCA.WebsiteUrl IS NOT NULL AND UCA.WebsiteUrl LIKE 'https://%' THEN 'SecureWebUser'
            WHEN UCA.AboutMe IS NOT NULL AND LENGTH(UCA.AboutMe) > 1000 THEN 'VerboseBioUser'
            WHEN UCA.Location IS NOT NULL AND UPPER(UCA.Location) LIKE '%INDIA%' THEN 'IndiaBasedUser'
            ELSE 'OtherUserInfo'
        END AS DerivedUserInfoCategory,
        AVG(CASE WHEN PEA.IsOwnerEdit AND PEA.UserEditRankAsc = 1 THEN PEA.HoursToEdit ELSE NULL END) AS AvgHoursToFirstSelfEdit
    FROM UserCoreActivity UCA
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(Id) AS TotalBadges,
            SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
            CAST(COUNT(Id) AS DECIMAL) / NULLIF(EXTRACT(DAY FROM AGE(MAX(Date), MIN(Date))) + 1, 0) AS BadgesPerDayActive
        FROM Badges
        GROUP BY UserId
    ) B ON UCA.UserId = B.UserId
    LEFT JOIN PostEditAnalysis PEA ON UCA.UserId = PEA.EditorUserId
    GROUP BY
        UCA.UserId, UCA.DisplayName, UCA.Reputation, UCA.UserCreationDate, UCA.LastAccessDate,
        UCA.Location, UCA.AboutMe, UCA.WebsiteUrl, UCA.TotalPostsOwned, UCA.TotalQuestionsOwned,
        UCA.TotalAnswersOwned, UCA.TotalPostViewsOwned, UCA.TotalPostScoreOwned,
        UCA.TotalCommentsOnOwnedPosts, UCA.TotalCommentsMadeByOwner, UCA.TotalUpVotesReceivedOnPosts,
        UCA.TotalDownVotesReceivedOnPosts, UCA.TotalUpVotesGiven, UCA.TotalDownVotesGiven,
        UCA.TotalFavoriteVotesGiven, B.TotalBadges, B.GoldBadges, B.SilverBadges, B.BronzeBadges,
        B.BadgesPerDayActive
),
FinalUserPerformance AS (
    SELECT
        AUM.UserId,
        AUM.DisplayName,
        AUM.Reputation,
        AUM.ReputationDecile,
        AUM.Location,
        AUM.DerivedUserInfoCategory,
        AUM.TotalPostsOwned,
        AUM.TotalQuestionsOwned,
        AUM.TotalAnswersOwned,
        AUM.TotalPostViewsOwned,
        AUM.TotalPostScoreOwned,
        AUM.TotalCommentsOnOwnedPosts,
        AUM.TotalCommentsMadeByOwner,
        AUM.TotalUpVotesReceivedOnPosts,
        AUM.TotalDownVotesReceivedOnPosts,
        AUM.TotalUpVotesGiven,
        AUM.TotalDownVotesGiven,
        AUM.TotalFavoriteVotesGiven,
        AUM.TotalBadges,
        AUM.GoldBadges,
        AUM.SilverBadges,
        AUM.BronzeBadges,
        AUM.BadgesPerDayActive,
        AUM.HasEverAcceptedAnswer,
        AUM.EditsOtherUsersPosts,
        AUM.SelfEditedPostsCount,
        AUM.AvgHoursToFirstSelfEdit,
        COALESCE(AVG(CASE WHEN QAE.AnswerScoreRank = 1 THEN EXTRACT(EPOCH FROM (QAE.AnswerCreationDate - QAE.QuestionCreationDate)) / 3600 END), 0) AS AvgHoursToFirstAnswer,
        COALESCE(AVG(QAE.MinsBetweenAnswers), 0) AS AvgMinsBetweenAnswersForOwnedQuestions,
        (
            SELECT COUNT(DISTINCT TRIM(SUBSTRING(t.tag, 2, LENGTH(t.tag) - 2)))
            FROM Posts P_tag
            CROSS JOIN LATERAL UNNEST(string_to_array(COALESCE(P_tag.Tags, ''), '><')) AS t(tag)
            WHERE P_tag.OwnerUserId = AUM.UserId
              AND P_tag.PostTypeId = 1
              AND COALESCE(P_tag.ViewCount, 0) > 1000
              AND LENGTH(TRIM(SUBSTRING(t.tag, 2, LENGTH(t.tag) - 2))) > 0
        ) AS DistinctPopularTagsUsed,
        (
            (AUM.TotalUpVotesReceivedOnPosts * 0.5) +
            (AUM.TotalCommentsOnOwnedPosts * 0.3) +
            (AUM.TotalAnswersOwned * 0.2) +
            (AUM.TotalQuestionsOwned * 0.1) -
            (AUM.TotalDownVotesReceivedOnPosts * 0.1)
        ) * (1 + (AUM.GoldBadges * 0.1 + AUM.SilverBadges * 0.05)) AS EngagementScore,
        COALESCE(AUM.DisplayName, 'Unknown') || ' (' || COALESCE(AUM.Location, 'N/A') || ')' AS UserDisplayInfo,
        CASE
            WHEN AUM.AboutMe IS NOT NULL AND LENGTH(AUM.AboutMe) > 200 THEN 'RichBio'
            WHEN AUM.AboutMe IS NOT NULL THEN 'BriefBio'
            ELSE 'NoBio'
        END AS AboutMeStatus
    FROM AggregatedUserMetrics AUM
    LEFT JOIN QuestionAnswerEngagement QAE ON AUM.UserId = QAE.QuestionOwnerId
    GROUP BY
        AUM.UserId, AUM.DisplayName, AUM.Reputation, AUM.ReputationDecile, AUM.Location,
        AUM.DerivedUserInfoCategory, AUM.TotalPostsOwned, AUM.TotalQuestionsOwned,
        AUM.TotalAnswersOwned, AUM.TotalPostViewsOwned, AUM.TotalPostScoreOwned,
        AUM.TotalCommentsOnOwnedPosts, AUM.TotalCommentsMadeByOwner, AUM.TotalUpVotesReceivedOnPosts,
        AUM.TotalDownVotesReceivedOnPosts, AUM.TotalUpVotesGiven, AUM.TotalDownVotesGiven,
        AUM.TotalFavoriteVotesGiven, AUM.TotalBadges, AUM.GoldBadges, AUM.SilverBadges,
        AUM.BronzeBadges, AUM.BadgesPerDayActive, AUM.HasEverAcceptedAnswer,
        AUM.EditsOtherUsersPosts, AUM.SelfEditedPostsCount, AUM.AvgHoursToFirstSelfEdit
),
TopTierUsers AS (
    SELECT *
    FROM FinalUserPerformance
    WHERE Reputation > 10000 AND TotalBadges > 100 AND EngagementScore > 500
),
RisingStars AS (
    SELECT *
    FROM FinalUserPerformance
    WHERE Reputation <= 10000 AND Reputation > 1000 AND TotalPostsOwned > 20 AND BadgesPerDayActive > 0.05
)
SELECT
    UserId,
    DisplayName,
    Reputation,
    ReputationDecile,
    UserDisplayInfo,
    TotalPostsOwned,
    TotalQuestionsOwned,
    TotalAnswersOwned,
    EngagementScore,
    DistinctPopularTagsUsed,
    AvgHoursToFirstAnswer,
    AboutMeStatus,
    'TopTier' AS UserCategory
FROM TopTierUsers
WHERE AvgHoursToFirstAnswer > 1
UNION ALL
SELECT
    UserId,
    DisplayName,
    Reputation,
    ReputationDecile,
    UserDisplayInfo,
    TotalPostsOwned,
    TotalQuestionsOwned,
    TotalAnswersOwned,
    EngagementScore,
    DistinctPopularTagsUsed,
    AvgHoursToFirstAnswer,
    AboutMeStatus,
    'RisingStar' AS UserCategory
FROM RisingStars
WHERE TotalAnswersOwned > TotalQuestionsOwned
  AND DistinctPopularTagsUsed > 5
  AND AvgHoursToFirstAnswer BETWEEN 0.5 AND 12
ORDER BY Reputation DESC, EngagementScore DESC
LIMIT 500;
