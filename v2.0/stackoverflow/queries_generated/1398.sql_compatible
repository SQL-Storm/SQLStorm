WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        (U.UpVotes + U.DownVotes) AS TotalVotesGivenByUser,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity,
        U.AboutMe,
        U.WebsiteUrl,
        U.Location
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.AboutMe, U.WebsiteUrl, U.Location
),
PostTagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        COALESCE(array_length(string_to_array(substring(P.Tags FROM 2 FOR char_length(P.Tags) - 2), '><'), 1), 0) AS TagCount,
        string_to_array(substring(P.Tags FROM 2 FOR char_length(P.Tags) - 2), '><') AS ParsedTags,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus,
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId, P.OwnerUserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByUserPostScore,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS LatestPostByUser
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
),
HistoricalPostEdits AS (
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 END) AS EditCount,
        MAX(PH.CreationDate) AS LastEditDate,
        MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (1,2,3)) AS InitialCreationHistoryDate,
        EXTRACT(EPOCH FROM (MAX(PH.CreationDate) - MIN(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (1,2,3)))) / 3600 AS HoursSinceInitialEdit
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    GROUP BY PH.PostId, PH.UserId
),
UserBadgeSummary AS (
    SELECT
        UserId,
        COUNT(DISTINCT Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN Class = 1 THEN Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN Class = 2 THEN Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN Class = 3 THEN Id END) AS BronzeBadges,
        MAX(Date) AS LastBadgeDate
    FROM Badges
    GROUP BY UserId
),
FinalUserMetrics AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalPostScore,
        UE.TotalPosts,
        UE.TotalQuestions,
        UE.TotalAnswers,
        UE.TotalCommentScore,
        UE.TotalComments,
        UE.TotalVotesGivenByUser,
        UE.UserCreationDate,
        UE.LastAccessDate,
        UE.AboutMe,
        UE.WebsiteUrl,
        UE.Location,
        COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
        UBS.LastBadgeDate,
        COALESCE(GREATEST(UE.LastPostActivity, UE.LastCommentActivity), UE.LastAccessDate) AS OverallLastActivityDate,
        (
            SELECT AVG(InnerP.Score)
            FROM Posts InnerP
            JOIN Users InnerU ON InnerP.OwnerUserId = InnerU.Id
            WHERE InnerP.PostTypeId = 1
              AND InnerU.CreationDate BETWEEN (UE.UserCreationDate - INTERVAL '1 year') AND UE.UserCreationDate
              AND InnerU.LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 months'
              AND InnerP.OwnerUserId <> UE.UserId
        ) AS AvgQuestionScorePeerGroup,
        CASE
            WHEN UE.AboutMe ILIKE '%developer%' OR UE.DisplayName ILIKE '%dev%' THEN 'Developer-Focused'
            WHEN UE.AboutMe ILIKE '%programmer%' OR UE.DisplayName ILIKE '%code%' THEN 'Programmer-Oriented'
            WHEN UE.Location IS NULL AND UE.WebsiteUrl IS NULL THEN 'Ghost-User'
            WHEN UE.Reputation > 50000 AND COALESCE(UBS.GoldBadges, 0) >= 5 THEN 'Elite-Contributor'
            ELSE 'General-Contributor'
        END AS UserArchetype,
        (
            SELECT COALESCE(AVG(HPE.EditCount), 0)
            FROM HistoricalPostEdits HPE
            JOIN Posts P_sub ON HPE.PostId = P_sub.Id
            WHERE P_sub.OwnerUserId = UE.UserId
        ) AS AvgEditsPerOwnedPost,
        (
            SELECT T.TagName
            FROM PostTagAnalysis PTA_sub,
                 unnest(PTA_sub.ParsedTags) AS tag_name
            JOIN Tags T ON T.TagName = tag_name
            WHERE PTA_sub.OwnerUserId = UE.UserId AND PTA_sub.PostTypeId = 1
            GROUP BY T.TagName
            ORDER BY COUNT(*) DESC, T.TagName
            LIMIT 1
        ) AS MostFrequentQuestionTag,
        RANK() OVER (ORDER BY UE.Reputation DESC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY UE.TotalPostScore DESC) AS PostScoreDecile,
        EXTRACT(DAY FROM (UE.LastAccessDate - COALESCE(GREATEST(UE.LastPostActivity, UE.LastCommentActivity), UE.LastAccessDate))) AS DaysSinceLastContentContribution
    FROM UserEngagement UE
    LEFT JOIN UserBadgeSummary UBS ON UE.UserId = UBS.UserId
)
SELECT
    FUM.UserId,
    FUM.DisplayName,
    FUM.Reputation,
    FUM.TotalPosts,
    FUM.TotalQuestions,
    FUM.TotalAnswers,
    FUM.GoldBadges,
    FUM.UserArchetype,
    FUM.MostFrequentQuestionTag,
    FUM.GlobalReputationRank,
    FUM.PostScoreDecile,
    FUM.DaysSinceLastContentContribution,
    'High Impact User' AS UserGroup,
    PTA_Q.PostId AS TopQuestionID,
    PTA_Q.PostScore AS TopQuestionScore,
    PTA_A.PostId AS TopAnswerID,
    PTA_A.PostScore AS TopAnswerScore,
    HPE.HoursSinceInitialEdit AS HoursToLastQuestionEdit,
    FUM.OverallLastActivityDate,
    FUM.UserCreationDate,
    FUM.LastAccessDate,
    FUM.TotalPostScore,
    FUM.TotalCommentScore,
    FUM.TotalVotesGivenByUser
FROM FinalUserMetrics FUM
LEFT JOIN PostTagAnalysis PTA_Q
    ON FUM.UserId = PTA_Q.OwnerUserId
    AND PTA_Q.PostTypeId = 1
    AND PTA_Q.RankByUserPostScore = 1
LEFT JOIN PostTagAnalysis PTA_A
    ON FUM.UserId = PTA_A.OwnerUserId
    AND PTA_A.PostTypeId = 2
    AND PTA_A.RankByUserPostScore = 1
LEFT JOIN HistoricalPostEdits HPE
    ON PTA_Q.PostId = HPE.PostId AND FUM.UserId = HPE.EditorUserId
WHERE FUM.Reputation > 10000
  AND FUM.GoldBadges >= 3
  AND FUM.OverallLastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
  AND FUM.TotalQuestions > 5
  AND FUM.TotalAnswers > 10
  AND (FUM.MostFrequentQuestionTag IS NOT NULL OR FUM.AvgEditsPerOwnedPost > 0)
  AND (FUM.WebsiteUrl IS NOT NULL OR FUM.AboutMe IS NOT NULL OR FUM.Location IS NOT NULL)

UNION ALL

SELECT
    FUM.UserId,
    FUM.DisplayName,
    FUM.Reputation,
    FUM.TotalPosts,
    FUM.TotalQuestions,
    FUM.TotalAnswers,
    FUM.GoldBadges,
    FUM.UserArchetype,
    FUM.MostFrequentQuestionTag,
    FUM.GlobalReputationRank,
    FUM.PostScoreDecile,
    FUM.DaysSinceLastContentContribution,
    'Emerging Contributor' AS UserGroup,
    PTA_Q.PostId AS TopQuestionID,
    PTA_Q.PostScore AS TopQuestionScore,
    PTA_A.PostId AS TopAnswerID,
    PTA_A.PostScore AS TopAnswerScore,
    HPE.HoursSinceInitialEdit AS HoursToLastQuestionEdit,
    FUM.OverallLastActivityDate,
    FUM.UserCreationDate,
    FUM.LastAccessDate,
    FUM.TotalPostScore,
    FUM.TotalCommentScore,
    FUM.TotalVotesGivenByUser
FROM FinalUserMetrics FUM
LEFT JOIN PostTagAnalysis PTA_Q
    ON FUM.UserId = PTA_Q.OwnerUserId
    AND PTA_Q.PostTypeId = 1
    AND PTA_Q.RankByUserPostScore = 1
LEFT JOIN PostTagAnalysis PTA_A
    ON FUM.UserId = PTA_A.OwnerUserId
    AND PTA_A.PostTypeId = 2
    AND PTA_A.RankByUserPostScore = 1
LEFT JOIN HistoricalPostEdits HPE
    ON PTA_Q.PostId = HPE.PostId AND FUM.UserId = HPE.EditorUserId
WHERE FUM.Reputation BETWEEN 1000 AND 10000
  AND FUM.GoldBadges <= 2
  AND FUM.OverallLastActivityDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
  AND FUM.TotalQuestions >= 1
  AND FUM.TotalAnswers >= 3
  AND COALESCE(FUM.AvgQuestionScorePeerGroup, 0) > 10
  AND FUM.UserArchetype IN ('Developer-Focused', 'Programmer-Oriented')

ORDER BY Reputation DESC, OverallLastActivityDate DESC, UserGroup;