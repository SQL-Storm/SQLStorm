WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(P.Score) AS TotalPostScore,
        COUNT(C.Id) AS TotalComments,
        AVG(C.Score) AS AverageCommentScore,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        CAST(
          FLOOR(
            EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - U.CreationDate)) / (60 * 60 * 24)
          ) AS INTEGER
        ) AS AccountAgeDays
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.OwnerUserId,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        CASE
          WHEN P.Tags IS NULL THEN 0
          ELSE array_length(string_to_array(substring(P.Tags FROM 2 FOR (length(P.Tags) - 2)), '><'), 1)
        END AS TagCount,
        CASE
            WHEN P.Score >= 100 THEN 'High'
            WHEN P.Score >= 20 THEN 'Medium'
            ELSE 'Low'
        END AS PostScoreCategory,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        CAST(
          FLOOR(
            EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - P.LastActivityDate)) / (60 * 60 * 24)
          ) AS INTEGER
        ) AS DaysSinceLastActivity,
        (SELECT U2.Reputation FROM Users U2 WHERE U2.Id = P.LastEditorUserId) AS LastEditorReputation,
        (SELECT AVG(A.Score) FROM Posts A WHERE A.ParentId = P.Id AND A.PostTypeId = 2) AS AverageAnswerScore,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS EditCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS LastClosedDateFromHistory
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    GROUP BY P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.OwnerUserId, P.LastEditDate, P.ClosedDate, P.CommunityOwnedDate, P.Tags, P.AcceptedAnswerId, P.LastActivityDate, P.LastEditorUserId
),
UserActivityTimelineWithLagLead AS (
    SELECT
        ActorUserId,
        ActivityType,
        ActivityId,
        ActivityDate,
        LAG(ActivityDate, 1) OVER (PARTITION BY ActorUserId ORDER BY ActivityDate) AS PrevActivityDate,
        LEAD(ActivityDate, 1) OVER (PARTITION BY ActorUserId ORDER BY ActivityDate) AS NextActivityDate
    FROM (
        SELECT
            P.OwnerUserId AS ActorUserId,
            'Post' AS ActivityType,
            P.Id AS ActivityId,
            P.CreationDate AS ActivityDate
        FROM Posts P
        WHERE P.OwnerUserId IS NOT NULL
        UNION ALL
        SELECT
            C.UserId AS ActorUserId,
            'Comment' AS ActivityType,
            C.Id AS ActivityId,
            C.CreationDate AS ActivityDate
        FROM Comments C
        WHERE C.UserId IS NOT NULL
    ) AS AllUserActivities
),
MostFrequentCloseReasonPerPost AS (
    SELECT
        PH.PostId,
        CR.Name AS CloseReasonName,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY COUNT(*) DESC, CR.Name) AS rn
    FROM PostHistory PH
    JOIN CloseReasonTypes CR ON PH.Comment = CAST(CR.Id AS VARCHAR)
    WHERE PH.PostHistoryTypeId = 10
    GROUP BY PH.PostId, CR.Name
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.AccountAgeDays,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalComments,
    UAS.AverageCommentScore,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    PDE.PostId,
    PDE.PostTypeId,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount,
    PDE.AnswerCount,
    PDE.CommentCount,
    PDE.FavoriteCount,
    PDE.TagCount,
    PDE.PostScoreCategory,
    PDE.HasAcceptedAnswer,
    PDE.DaysSinceLastActivity,
    PDE.LastEditorReputation,
    PDE.AverageAnswerScore,
    PDE.EditCount,
    PDE.CloseVoteCount,
    PDE.ReopenVoteCount,
    ROW_NUMBER() OVER (PARTITION BY UAS.UserId ORDER BY PDE.PostScore DESC, PDE.PostCreationDate DESC) AS UserPostRank,
    RANK() OVER (PARTITION BY PDE.PostTypeId ORDER BY PDE.PostScore DESC) AS PostTypeScoreRank,
    UAT.PrevActivityDate AS PostSpecificPrevActivityDate,
    UAT.NextActivityDate AS PostSpecificNextActivityDate,
    AVG(PDE.PostScore) OVER (PARTITION BY UAS.UserId) AS AvgUserPostScore,
    SUM(PDE.ViewCount) OVER (PARTITION BY UAS.UserId ORDER BY PDE.PostCreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningTotalUserViews,
    COALESCE(UAS.DisplayName, 'Anonymous') || ' (' || COALESCE(U.Location, 'Unknown Location') || ')' AS UserLocationInfo,
    NULLIF(PDE.PostScore, 0) AS NonZeroPostScore,
    CASE
        WHEN PDE.ClosedDate IS NOT NULL AND PDE.CommunityOwnedDate IS NOT NULL THEN 'Closed & CommunityOwned'
        WHEN PDE.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN PDE.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
        WHEN PDE.FavoriteCount > 50 AND PDE.AverageAnswerScore > 10 AND PDE.PostTypeId = 1 THEN 'Highly Engaged Question'
        WHEN PDE.ViewCount > 10000 OR PDE.PostScore > 50 THEN 'HighVisibility'
        WHEN PDE.PostScore < 0 THEN 'NegativeScore'
        ELSE 'Standard'
    END AS PostStatusClassification,
    MFR.CloseReasonName,
    CASE
        WHEN PDE.CloseVoteCount > 0 AND EXISTS (
            SELECT 1 FROM PostLinks PL WHERE PL.PostId = PDE.PostId AND PL.LinkTypeId = 3
        ) THEN 'Closed & Duplicated'
        WHEN PDE.EditCount > 5 AND PDE.PostScore < 0 AND PDE.DaysSinceLastActivity > 365 THEN 'Stale & Controversial'
        ELSE 'Normal'
    END AS PostControversyFlag,
    EXISTS (
        SELECT 1
        FROM Posts RelatedP
        JOIN PostLinks PL ON RelatedP.Id = PL.RelatedPostId
        WHERE PL.PostId = PDE.PostId
        AND RelatedP.Score > PDE.PostScore * 2
        AND RelatedP.PostTypeId = PDE.PostTypeId
    ) AS HasMuchHigherScoredRelatedPost
FROM UserActivitySummary UAS
INNER JOIN Users U ON UAS.UserId = U.Id
LEFT JOIN PostDetailsExtended PDE ON UAS.UserId = PDE.OwnerUserId
LEFT JOIN UserActivityTimelineWithLagLead UAT ON UAS.UserId = UAT.ActorUserId
    AND UAT.ActivityType = 'Post' AND UAT.ActivityId = PDE.PostId
LEFT JOIN MostFrequentCloseReasonPerPost MFR ON PDE.PostId = MFR.PostId AND MFR.rn = 1
WHERE
    UAS.TotalPosts > 0
    AND UAS.Reputation > 1000
    AND PDE.PostId IS NOT NULL
    AND (
        PDE.DaysSinceLastActivity < 365
        OR PDE.PostScore > 10
        OR UAS.GoldBadges > 0
        OR (PDE.CloseVoteCount > 0 AND PDE.ReopenVoteCount > 0)
    )
    AND (U.Location IS NOT NULL OR UAS.AverageCommentScore IS NOT NULL)
GROUP BY
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.AccountAgeDays,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalPostScore,
    UAS.TotalComments,
    UAS.AverageCommentScore,
    UAS.GoldBadges,
    UAS.SilverBadges,
    UAS.BronzeBadges,
    PDE.PostId,
    PDE.PostTypeId,
    PDE.PostCreationDate,
    PDE.PostScore,
    PDE.ViewCount,
    PDE.AnswerCount,
    PDE.CommentCount,
    PDE.FavoriteCount,
    PDE.TagCount,
    PDE.PostScoreCategory,
    PDE.HasAcceptedAnswer,
    PDE.DaysSinceLastActivity,
    PDE.LastEditorReputation,
    PDE.AverageAnswerScore,
    PDE.EditCount,
    PDE.CloseVoteCount,
    PDE.ReopenVoteCount,
    UAT.PrevActivityDate,
    UAT.NextActivityDate,
    U.Location,
    PDE.ClosedDate,
    PDE.CommunityOwnedDate,
    PDE.FavoriteCount,
    MFR.CloseReasonName,
    PDE.DaysSinceLastActivity,
    UAS.LastPostDate
ORDER BY
    UAS.Reputation DESC,
    UAT.PrevActivityDate DESC,
    PDE.PostScore DESC,
    UAS.LastPostDate DESC;