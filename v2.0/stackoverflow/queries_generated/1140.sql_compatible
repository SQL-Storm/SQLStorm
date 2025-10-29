WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.UpVotes,
        U.DownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        MAX(P.CreationDate) AS LastPostDate,
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        COUNT(C.Id) AS TotalCommentsMade
    FROM Users U
    INNER JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.UpVotes, U.DownVotes
    HAVING COUNT(DISTINCT P.Id) > 5
),
PostModerationEvents AS (
    SELECT
        PH.PostId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PHT.Name AS EventTypeName,
        PH.UserId AS ModeratorUserId,
        PH.Comment AS CloseReasonComment,
        CR.Name AS CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId ORDER BY PH.CreationDate DESC) as rn
    FROM PostHistory PH
    INNER JOIN PostHistoryTypes PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CR.Id AS VARCHAR)
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13)
),
LatestPostModeration AS (
    SELECT
        PostId,
        EventDate,
        EventTypeName,
        ModeratorUserId,
        CloseReasonName
    FROM PostModerationEvents
    WHERE rn = 1
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
        STRING_AGG(CASE WHEN B.Class = 1 THEN B.Name ELSE NULL END, ', ' ORDER BY B.Name) AS GoldBadgeNames,
        STRING_AGG(CASE WHEN B.Class = 2 THEN B.Name ELSE NULL END, ', ' ORDER BY B.Name) AS SilverBadgeNames
    FROM Badges B
    GROUP BY B.UserId
),
TopTagsByPost AS (
    SELECT
        P.OwnerUserId AS UserId,
        TRIM(unnest(string_to_array(substring(P.Tags, 2, length(P.Tags)-2), '><'))) AS TagName,
        P.Id AS PostId
    FROM Posts P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
),
UserTopTag AS (
    SELECT
        UserId,
        TagName,
        COUNT(PostId) AS TagUsageCount,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY COUNT(PostId) DESC, TagName ASC) as rn
    FROM TopTagsByPost
    GROUP BY UserId, TagName
),
UsersWithEditedPosts AS (
    SELECT DISTINCT PH.UserId
    FROM PostHistory PH
    WHERE PH.PostHistoryTypeId IN (4, 5, 6)
),
UsersWithClosedPosts AS (
    SELECT DISTINCT P.OwnerUserId AS UserId
    FROM PostHistory PH
    INNER JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.PostHistoryTypeId = 10 AND P.PostTypeId = 1
),
UsersWhoEditButNoClosedQuestions AS (
    SELECT UserId FROM UsersWithEditedPosts
    EXCEPT
    SELECT UserId FROM UsersWithClosedPosts
)
SELECT
    UA.UserId,
    UA.DisplayName,
    UA.Reputation,
    UA.UserCreationDate,
    UA.TotalPosts,
    UA.QuestionsPosted,
    UA.AnswersPosted,
    UA.TotalPostScore,
    UA.TotalPostViews,
    UA.AvgQuestionScore,
    UA.AvgAnswerScore,
    COALESCE(UBS.TotalBadges, 0) AS UserTotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS UserGoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS UserSilverBadges,
    UBS.GoldBadgeNames,
    UBS.SilverBadgeNames,
    UTT.TagName AS MostFrequentQuestionTag,
    UTT.TagUsageCount AS MostFrequentQuestionTagCount,
    (SELECT COUNT(DISTINCT V.PostId) FROM Votes V WHERE V.UserId = UA.UserId AND V.VoteTypeId = 5) AS TotalFavoritePosts,
    (SELECT COUNT(DISTINCT P.Id) FROM Posts P WHERE P.OwnerUserId = UA.UserId AND P.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers,
    (SELECT AVG(EXTRACT(EPOCH FROM (A.CreationDate - Q.CreationDate))) / 3600.0
     FROM Posts Q
     INNER JOIN Posts A ON Q.AcceptedAnswerId = A.Id
     WHERE Q.OwnerUserId = UA.UserId AND Q.PostTypeId = 1 AND Q.AcceptedAnswerId IS NOT NULL
    ) AS AvgTimeToAcceptAnswerHours,
    (SELECT STRING_AGG(DISTINCT T_inner.TagName, ', ' ORDER BY T_inner.TagName)
     FROM TopTagsByPost TTP_inner
     INNER JOIN Posts P_inner ON TTP_inner.PostId = P_inner.Id
     INNER JOIN Tags T_inner ON TTP_inner.TagName = T_inner.TagName
     WHERE P_inner.OwnerUserId = UA.UserId AND P_inner.PostTypeId = 1
       AND P_inner.Score > (SELECT AVG(P_avg.Score) FROM Posts P_avg WHERE P_avg.PostTypeId = 1)
    ) AS PopularQuestionTags,
    LP.EventTypeName AS LatestModerationEventType,
    LP.EventDate AS LatestModerationEventDate,
    LP.CloseReasonName AS LatestModerationCloseReason,
    CASE
        WHEN UA.Reputation > 10000 AND COALESCE(UBS.GoldBadges, 0) >= 3 THEN 'Guru'
        WHEN UA.Reputation > 2000 AND COALESCE(UBS.SilverBadges, 0) >= 5 THEN 'Expert'
        WHEN UA.Reputation > 500 AND UA.TotalPosts >= 20 THEN 'Contributor'
        ELSE 'Engaged'
    END AS UserCategory,
    UA.TotalCommentsMade,
    (UA.UpVotes - UA.DownVotes) AS NetVotesReceived,
    PH_lag.PreviousEditDate,
    PH_lag.CurrentEditDate,
    EXTRACT(EPOCH FROM (PH_lag.CurrentEditDate - PH_lag.PreviousEditDate)) / 60.0 AS MinutesBetweenEdits,
    NULLIF(TRIM(SUBSTRING(U.AboutMe, POSITION('<p>' IN U.AboutMe) + 3, POSITION('</p>' IN U.AboutMe) - (POSITION('<p>' IN U.AboutMe) + 3))), '') AS AboutMeFirstParagraph,
    P_AccAns.Id AS LastAcceptedAnswerPostId,
    P_AccAns.Score AS LastAcceptedAnswerScore
FROM UserActivity UA
INNER JOIN Users U ON UA.UserId = U.Id
LEFT JOIN UserBadgeSummary UBS ON UA.UserId = UBS.UserId
LEFT JOIN (SELECT UserId, TagName, TagUsageCount FROM UserTopTag WHERE rn = 1) UTT ON UA.UserId = UTT.UserId
LEFT JOIN LATERAL (
    SELECT LPM.EventTypeName, LPM.EventDate, LPM.CloseReasonName
    FROM LatestPostModeration LPM
    INNER JOIN Posts P ON LPM.PostId = P.Id
    WHERE P.OwnerUserId = UA.UserId
    ORDER BY LPM.EventDate DESC
    LIMIT 1
) LP ON TRUE
LEFT JOIN LATERAL (
    SELECT P_Q.AcceptedAnswerId, P_A.Id, P_A.Score
    FROM Posts P_Q
    INNER JOIN Posts P_A ON P_Q.AcceptedAnswerId = P_A.Id
    WHERE P_Q.OwnerUserId = UA.UserId
      AND P_Q.PostTypeId = 1
      AND P_Q.AcceptedAnswerId IS NOT NULL
    ORDER BY P_Q.CreationDate DESC
    LIMIT 1
) P_AccAns ON TRUE
LEFT JOIN LATERAL (
    SELECT
        PH_inner.PostId,
        PH_inner.CreationDate AS CurrentEditDate,
        LAG(PH_inner.CreationDate, 1) OVER (PARTITION BY PH_inner.PostId ORDER BY PH_inner.CreationDate) AS PreviousEditDate
    FROM PostHistory PH_inner
    WHERE PH_inner.UserId = UA.UserId
      AND PH_inner.PostHistoryTypeId IN (4, 5, 6)
    ORDER BY PH_inner.CreationDate DESC
    LIMIT 1
) PH_lag ON TRUE
WHERE
    UA.TotalPostScore > 500
    AND UA.Reputation > 1000
    AND EXISTS (
        SELECT 1
        FROM Badges B_ex
        WHERE B_ex.UserId = UA.UserId AND B_ex.Class = 1
    )
    AND (
        (U.Location IS NOT NULL
         AND LENGTH(U.Location) > 5
         AND UPPER(SUBSTRING(U.Location, 1, 1)) IN ('N', 'S', 'E', 'W'))
        OR (UA.UserCreationDate > DATE '2018-01-01' AND COALESCE(UA.AvgQuestionScore, 0) > 10)
    )
    AND UA.UserId IN (SELECT UserId FROM UsersWhoEditButNoClosedQuestions)
ORDER BY UA.Reputation DESC, UA.LastPostDate DESC
LIMIT 100;