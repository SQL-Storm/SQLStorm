WITH UserEngagement AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        DATE_PART('day', U.LastAccessDate - U.CreationDate) AS DaysSinceCreation,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersProvided,
        COALESCE(SUM(CASE WHEN P.PostTypeId IN (1, 2) THEN P.Score ELSE 0 END), 0) AS TotalPostScore,
        COALESCE(AVG(NULLIF(P.Score, NULL)) FILTER (WHERE P.PostTypeId IN (1, 2)), 0.0) AS AvgPostScore,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        (
            SELECT COUNT(DISTINCT plink.RelatedPostId)
            FROM PostLinks plink
            WHERE plink.PostId IN (
                SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = U.Id
            )
              AND plink.LinkTypeId = 1
        ) AS OutgoingLinksFromUserPosts,
        (
            SELECT COUNT(DISTINCT plink.PostId)
            FROM PostLinks plink
            WHERE plink.RelatedPostId IN (
                SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = U.Id
            )
              AND plink.LinkTypeId = 1
        ) AS IncomingLinksToUserPosts
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostLifeCycle AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        DATE_PART('day', P.LastEditDate - P.CreationDate) AS DaysToFirstEdit,
        DATE_PART('day', P.ClosedDate - P.CreationDate) AS DaysToClosure,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        MAX(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS WasDeleted,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId BETWEEN 4 AND 9) AS EditHistoryCount,
        (
            SELECT COALESCE(SUM(C_corr.Score), 0)
            FROM Comments C_corr
            WHERE C_corr.PostId = P.Id
              AND C_corr.CreationDate BETWEEN P.CreationDate AND P.CreationDate + INTERVAL '24 hours'
        ) AS InitialCommentScoreSum,
        RANK() OVER (PARTITION BY P.PostTypeId, EXTRACT(YEAR FROM P.CreationDate) ORDER BY P.ViewCount DESC NULLS LAST) AS ViewCountRankByYearAndType
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.LastEditDate, P.ClosedDate, P.ViewCount
),
TagAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        STRING_AGG(T.TagName, ';') AS TagsUsed,
        COUNT(DISTINCT T.Id) AS UniqueTagCount,
        AVG(LENGTH(T.TagName)) AS AvgTagNameLength,
        SUM(T.Count) AS TotalTagUsageCount
    FROM Posts P
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (CHAR_LENGTH(P.Tags) - 2)), '><')) AS TagName_unnested
    ) AS unn
    JOIN Tags T ON unn.TagName_unnested = T.TagName
    WHERE P.PostTypeId = 1
    GROUP BY P.Id, P.PostTypeId, P.OwnerUserId
),
VoteControversy AS (
    /* To avoid using a window function inside an aggregate, compute time gaps per vote row in a subquery, then aggregate. */
    SELECT
        Vc.PostId,
        Vc.OwnerUserId,
        SUM(CASE WHEN Vc.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN Vc.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        (SUM(CASE WHEN Vc.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN Vc.VoteTypeId = 3 THEN 1 ELSE 0 END)) AS NetVotes,
        NULLIF(CAST(SUM(CASE WHEN Vc.VoteTypeId = 2 THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN Vc.VoteTypeId = 3 THEN 1 ELSE 0 END), 0), 0) AS UpvoteDownvoteRatio,
        AVG(Vc.SecondsSincePrevVote) FILTER (WHERE Vc.VoteTypeId IN (2,3) AND Vc.SecondsSincePrevVote IS NOT NULL) AS AvgTimeBetweenVotesSeconds
    FROM (
        SELECT
            V.PostId,
            P.OwnerUserId,
            V.VoteTypeId,
            V.CreationDate,
            EXTRACT(EPOCH FROM (V.CreationDate - LAG(V.CreationDate) OVER (PARTITION BY V.PostId ORDER BY V.CreationDate))) AS SecondsSincePrevVote
        FROM Votes V
        JOIN Posts P ON V.PostId = P.Id
        WHERE V.VoteTypeId IN (2,3)
    ) Vc
    GROUP BY Vc.PostId, Vc.OwnerUserId
),
UserInteractionSummary AS (
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.DaysSinceCreation,
        UE.TotalQuestionsAsked,
        UE.TotalAnswersProvided,
        UE.TotalCommentsMade,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        UE.OutgoingLinksFromUserPosts,
        UE.IncomingLinksToUserPosts,
        PL.PostId,
        PL.PostTypeId,
        PL.PostCreationDate,
        PL.DaysToFirstEdit,
        PL.DaysToClosure,
        PL.WasClosed,
        PL.WasReopened,
        PL.WasDeleted,
        PL.EditHistoryCount,
        PL.InitialCommentScoreSum,
        PL.ViewCountRankByYearAndType,
        TA.TagsUsed,
        TA.UniqueTagCount,
        TA.AvgTagNameLength,
        TA.TotalTagUsageCount,
        VC.UpvotesReceived,
        VC.DownvotesReceived,
        VC.NetVotes,
        VC.UpvoteDownvoteRatio,
        VC.AvgTimeBetweenVotesSeconds
    FROM UserEngagement UE
    LEFT JOIN PostLifeCycle PL ON UE.UserId = PL.OwnerUserId
    LEFT JOIN TagAnalysis TA ON PL.PostId = TA.PostId AND PL.PostTypeId = TA.PostTypeId
    LEFT JOIN VoteControversy VC ON PL.PostId = VC.PostId
)
SELECT
    UIS.UserId,
    UIS.DisplayName,
    UIS.Reputation,
    UIS.DaysSinceCreation,
    UIS.TotalQuestionsAsked,
    UIS.TotalAnswersProvided,
    UIS.TotalCommentsMade,
    UIS.GoldBadges,
    UIS.SilverBadges,
    UIS.BronzeBadges,
    (
        (UIS.TotalQuestionsAsked * 5) +
        (UIS.TotalAnswersProvided * 3) +
        (UIS.TotalCommentsMade * 1) +
        (COALESCE(UIS.GoldBadges, 0) * 10) +
        (COALESCE(UIS.SilverBadges, 0) * 5) +
        (COALESCE(UIS.BronzeBadges, 0) * 2)
    ) AS UserActivityIndex,
    COALESCE(SUM(CASE WHEN UIS.PostTypeId = 1 THEN UIS.NetVotes ELSE 0 END), 0) AS UserQuestionNetVotes,
    COALESCE(SUM(CASE WHEN UIS.PostTypeId = 2 THEN UIS.NetVotes ELSE 0 END), 0) AS UserAnswerNetVotes,
    COALESCE(AVG(UIS.InitialCommentScoreSum) FILTER (WHERE UIS.PostTypeId IN (1,2)), 0.0) AS AvgInitialCommentScoreForUserPosts,
    COALESCE(COUNT(DISTINCT UIS.PostId) FILTER (WHERE UIS.WasClosed = 1), 0) AS TotalClosedPostsByThisUser,
    COALESCE(AVG(UIS.DaysToClosure) FILTER (WHERE UIS.WasClosed = 1), 0.0) AS AvgDaysToClosureForUserPosts,
    COALESCE(
        SUBSTRING(
            STRING_AGG(DISTINCT LEFT(UIS.TagsUsed, 20), ', ')
            FILTER (WHERE UIS.TagsUsed IS NOT NULL),
            1, 100
        ),
    'No Tags') AS SampleTopTags,
    (
        SELECT
            CASE WHEN COUNT(DISTINCT PH_sub.PostId) > 0 THEN 'Yes' ELSE 'No' END
        FROM PostHistory PH_sub
        WHERE PH_sub.PostId IN (
            SELECT P_sub.Id FROM Posts P_sub WHERE P_sub.OwnerUserId = UIS.UserId
        )
          AND PH_sub.PostHistoryTypeId IN (4, 5, 6)
          AND PH_sub.UserId IS DISTINCT FROM UIS.UserId
        GROUP BY PH_sub.UserId
        HAVING COUNT(PH_sub.Id) > 5
    ) AS HasPostsEditedManyTimesByOthers,
    NULLIF(
        CAST(SUM(CASE WHEN UIS.UpvotesReceived > COALESCE(UIS.DownvotesReceived,0) THEN 1 ELSE 0 END) AS NUMERIC) /
        NULLIF(COUNT(DISTINCT UIS.PostId) FILTER (WHERE UIS.UpvotesReceived IS NOT NULL OR UIS.DownvotesReceived IS NOT NULL), 0),
    0) AS PostPositiveVoteRatio
FROM UserInteractionSummary UIS
WHERE
    UIS.Reputation > 1000
    AND UIS.DaysSinceCreation > 365
    AND UIS.TotalQuestionsAsked + UIS.TotalAnswersProvided + UIS.TotalCommentsMade > 10
    AND (
        (UIS.PostTypeId = 1 AND UIS.AvgTagNameLength IS NOT NULL AND UIS.AvgTagNameLength > 5)
        OR (UIS.PostTypeId = 2 AND UIS.WasDeleted = 0)
    )
    AND UIS.ViewCountRankByYearAndType <= 1000
GROUP BY
    UIS.UserId,
    UIS.DisplayName,
    UIS.Reputation,
    UIS.DaysSinceCreation,
    UIS.TotalQuestionsAsked,
    UIS.TotalAnswersProvided,
    UIS.TotalCommentsMade,
    UIS.GoldBadges,
    UIS.SilverBadges,
    UIS.BronzeBadges,
    UIS.OutgoingLinksFromUserPosts,
    UIS.IncomingLinksToUserPosts,
    UIS.PostId,
    UIS.PostTypeId,
    UIS.PostCreationDate,
    UIS.DaysToFirstEdit,
    UIS.DaysToClosure,
    UIS.WasClosed,
    UIS.WasReopened,
    UIS.WasDeleted,
    UIS.EditHistoryCount,
    UIS.InitialCommentScoreSum,
    UIS.ViewCountRankByYearAndType,
    UIS.TagsUsed,
    UIS.UniqueTagCount,
    UIS.AvgTagNameLength,
    UIS.TotalTagUsageCount,
    UIS.UpvotesReceived,
    UIS.DownvotesReceived,
    UIS.NetVotes,
    UIS.UpvoteDownvoteRatio,
    UIS.AvgTimeBetweenVotesSeconds
HAVING
    COUNT(DISTINCT UIS.PostId) > 5
    AND COALESCE(SUM(CASE WHEN UIS.PostTypeId = 1 THEN UIS.NetVotes ELSE 0 END), 0) > 50
ORDER BY
    UserActivityIndex DESC, TotalClosedPostsByThisUser ASC
LIMIT 100;