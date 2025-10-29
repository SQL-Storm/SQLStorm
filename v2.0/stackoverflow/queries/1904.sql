WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName AS UserDisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        COALESCE(U.WebsiteUrl, 'N/A') AS UserWebsiteUrl,
        U.Location,
        LENGTH(COALESCE(U.AboutMe, '')) AS AboutMeLength,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(P_owner.Score) FILTER (WHERE P_owner.OwnerUserId = U.Id AND P_owner.PostTypeId IN (1, 2)) AS AvgPostScoreByUser,
        (SELECT COUNT(DISTINCT PH.PostId) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (4,5,6,9)) AS TotalEditsMadeCount,
        (SELECT COUNT(DISTINCT P_vote.Id) FROM Posts P_vote WHERE P_vote.OwnerUserId = U.Id AND P_vote.Score < 0) AS NegativePostsCount
    FROM
        Users U
    LEFT JOIN
        Badges B ON U.Id = B.UserId
    LEFT JOIN
        Posts P_owner ON U.Id = P_owner.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.ParentId,
        P.AcceptedAnswerId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.OwnerUserId,
        COALESCE(P.OwnerDisplayName, 'Community') AS PostOwnerDisplayName,
        P.LastActivityDate,
        P.LastEditDate,
        P.Title,
        P.Tags,
        CASE WHEN P.ViewCount IS NULL OR P.AnswerCount IS NULL OR P.AnswerCount = 0 THEN 0 ELSE CAST(P.ViewCount AS NUMERIC) / NULLIF(P.AnswerCount, 0) END AS ViewPerAnswerRatio,
        LENGTH(P.Body) AS BodyLength,
        (CASE WHEN P.Tags IS NULL THEN 0 ELSE array_length(string_to_array(substring(P.Tags FROM 2 FOR char_length(P.Tags)-2), '><'), 1) END) AS NumberOfTags,
        (SELECT AVG(P2.Score) FROM Posts P2 WHERE P2.OwnerUserId = P.OwnerUserId AND P2.Id != P.Id AND P2.PostTypeId = P.PostTypeId) AS AvgSiblingPostScore,
        EXISTS (SELECT 1 FROM Comments C WHERE C.PostId = P.Id AND C.Score < 0 AND LOWER(C.Text) LIKE '%spam%') AS HasSpamFlaggedComments,
        (P.ClosedDate IS NOT NULL) AS IsClosed,
        (P.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned,
        (SELECT SUM(V.BountyAmount) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 8) AS TotalBountyAmount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount
    FROM
        Posts P
    WHERE
        P.PostTypeId IN (1, 2)
),
ModerationHistoryAggregated AS (
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (10, 12, 14, 19, 35) THEN 1 ELSE 0 END) AS NegativeModerationActions,
        MAX(PH.CreationDate) AS LastModerationActionDate,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CRT.Name ELSE NULL END) AS LastCloseReason,
        COUNT(DISTINCT PH.UserId) AS DistinctModeratorsAffected,
        MIN(PH.CreationDate) AS Min_PH_CreationDate,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment = CAST(CRT.Id AS TEXT)
    WHERE
        PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY
        PH.PostId
),
AcceptedAnswerDetails AS (
    SELECT
        Q.Id AS QuestionId,
        Q.AcceptedAnswerId,
        A.OwnerUserId AS AcceptedAnswerOwnerId,
        A.Score AS AcceptedAnswerScore,
        A.CreationDate AS AcceptedAnswerCreationDate,
        (A.CreationDate - Q.CreationDate) AS TimeToAcceptance,
        Q.OwnerUserId AS QuestionOwnerId
    FROM
        Posts Q
    JOIN
        Posts A ON Q.AcceptedAnswerId = A.Id
    WHERE
        Q.PostTypeId = 1 AND Q.AcceptedAnswerId IS NOT NULL
),
PostLinkSummary AS (
    SELECT
        PL.PostId,
        COUNT(PL.Id) AS TotalLinks,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromOtherPosts,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks
    FROM
        PostLinks PL
    GROUP BY
        PL.PostId
),
CommentSummary AS (
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        AVG(C.Score) AS AvgCommentScore,
        COUNT(DISTINCT C.UserId) AS DistinctCommenters,
        MAX(C.CreationDate) AS LastCommentDate,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%excellent%' OR LOWER(C.Text) LIKE '%helpful%' OR LOWER(C.Text) LIKE '%thanks%' THEN 1 ELSE 0 END) AS PositiveCommentsCount,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' OR LOWER(C.Text) LIKE '%wrong%' OR LOWER(C.Text) LIKE '%issue%' THEN 1 ELSE 0 END) AS NegativeCommentsCount
    FROM
        Comments C
    GROUP BY
        C.PostId
),
ModerationHistoryAggregated_Final AS (
    SELECT
        mha.PostId,
        mha.TotalHistoryEntries,
        mha.NegativeModerationActions,
        mha.LastModerationActionDate,
        mha.LastCloseReason,
        mha.DistinctModeratorsAffected,
        mha.CloseCount,
        -- compute time between last two actions using aggregated max dates window
        (mha.LastModerationActionDate - LAG(mha.LastModerationActionDate) OVER (PARTITION BY mha.PostId ORDER BY mha.LastModerationActionDate)) AS TimeBetweenLastTwoActions,
        prev.PreviousHistoryEntryDate
    FROM (
        SELECT
            m.PostId,
            m.TotalHistoryEntries,
            m.NegativeModerationActions,
            m.LastModerationActionDate,
            m.LastCloseReason,
            m.DistinctModeratorsAffected,
            m.CloseCount,
            m.Min_PH_CreationDate
        FROM ModerationHistoryAggregated m
    ) mha
    LEFT JOIN (
        SELECT
            ph2.PostId,
            LAG(ph2.CreationDate, 1, TIMESTAMP '1970-01-01 00:00:00') OVER (PARTITION BY ph2.PostId ORDER BY ph2.CreationDate) AS PreviousHistoryEntryDate
        FROM PostHistory ph2
        WHERE ph2.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    ) prev ON mha.PostId = prev.PostId
),
MainPostAnalysis AS (
    SELECT
        PEM.PostId,
        PT.Name AS PostTypeName,
        PEM.PostTypeId,
        PEM.Title,
        PEM.PostScore,
        PEM.ViewCount,
        PEM.AnswerCount,
        PEM.PostCommentCount,
        PEM.PostFavoriteCount,
        PEM.UpVoteCount,
        PEM.DownVoteCount,
        PEM.OwnerUserId,
        COALESCE(UAS.UserDisplayName, PEM.PostOwnerDisplayName) AS PostOwnerFinalDisplayName,
        UAS.Reputation AS PostOwnerReputation,
        UAS.TotalBadges AS PostOwnerTotalBadges,
        PEM.PostCreationDate,
        PEM.LastActivityDate,
        (PEM.LastActivityDate - PEM.PostCreationDate) AS TimeSinceCreationActivity,
        PEM.ViewPerAnswerRatio,
        PEM.BodyLength,
        PEM.NumberOfTags,
        REPLACE(TRIM(SUBSTRING(PEM.Tags FROM 2 FOR CHAR_LENGTH(PEM.Tags)-2)), '><', ', ') AS FormattedTags,
        PEM.AvgSiblingPostScore,
        PEM.HasSpamFlaggedComments,
        PEM.IsClosed,
        PEM.IsCommunityOwned,
        PEM.TotalBountyAmount,
        AAD.AcceptedAnswerId,
        AAD.AcceptedAnswerScore,
        AAD.TimeToAcceptance,
        COALESCE(MHA.TotalHistoryEntries, 0) AS PostHistoryCount,
        COALESCE(MHA.NegativeModerationActions, 0) AS NegativeModerationActions,
        MHA.LastModerationActionDate,
        MHA.LastCloseReason,
        COALESCE(MHA.CloseCount, 0) AS CloseCount,
        COALESCE(PLS.TotalLinks, 0) AS TotalLinkedPosts,
        COALESCE(PLS.LinkedFromOtherPosts, 0) AS LinkedFromThisPost,
        COALESCE(PLS.DuplicateLinks, 0) AS DuplicateOfThisPost,
        COALESCE(CS.TotalComments, 0) AS AllCommentTotalCount,
        COALESCE(CS.AvgCommentScore, 0.0) AS AvgCommentScore,
        COALESCE(CS.PositiveCommentsCount, 0) AS PositiveCommentsCount,
        COALESCE(CS.NegativeCommentsCount, 0) AS NegativeCommentsCount,
        MHA.TimeBetweenLastTwoActions AS ModerationTimeDelta,
        NULLIF(
            (CAST(PEM.UpVoteCount AS NUMERIC) - PEM.DownVoteCount) / NULLIF(PEM.PostCommentCount + PEM.ViewCount / 100 + PEM.AnswerCount * 2 + 1, 0)
            , 0) AS EngagementScoreMetric,
        CASE
            WHEN PEM.PostTypeId = 1 AND PEM.PostScore > 100 AND PEM.ViewCount > 5000 AND PEM.AnswerCount > 5 AND PEM.PostFavoriteCount > 10 AND COALESCE(UAS.Reputation,0) > 5000 THEN 'Highly Engaged Question'
            WHEN PEM.PostTypeId = 2 AND PEM.PostScore > 50 AND AAD.AcceptedAnswerId IS NOT NULL AND COALESCE(UAS.Reputation,0) > 2000 AND PEM.BodyLength > 500 THEN 'Top Accepted Answer'
            WHEN COALESCE(MHA.CloseCount, 0) > 0 OR COALESCE(MHA.NegativeModerationActions, 0) > 0 THEN 'Moderated Content'
            ELSE 'Standard Content'
        END AS ContentAnalysisCategory,
        COALESCE(UAS.Location, 'Unknown Region') AS UserLocation,
        CASE
            WHEN PEM.Tags LIKE '%<sql>%' AND (PEM.Tags LIKE '%<performance>%' OR PEM.Tags LIKE '%<optimization>%') THEN 'SQL Performance Topic'
            WHEN PEM.Tags LIKE '%<python>%' AND PEM.Tags LIKE '%<machine-learning>%' THEN 'Python ML Topic'
            WHEN PEM.Tags IS NULL OR CHAR_LENGTH(PEM.Tags) < 5 THEN 'Untagged/Generic'
            ELSE 'Other Specific Topic'
        END AS PrimaryTopicGroup,
        (SELECT COUNT(DISTINCT U_voter.Id) FROM Users U_voter JOIN Votes V_u ON U_voter.Id = V_u.UserId WHERE V_u.PostId = PEM.PostId AND V_u.VoteTypeId = 2) AS UniqueUpVoters
    FROM
        PostEngagementMetrics PEM
    JOIN
        PostTypes PT ON PEM.PostTypeId = PT.Id
    LEFT JOIN
        UserActivitySummary UAS ON PEM.OwnerUserId = UAS.UserId
    LEFT JOIN
        ModerationHistoryAggregated_Final MHA ON PEM.PostId = MHA.PostId
    LEFT JOIN
        AcceptedAnswerDetails AAD ON PEM.PostId = AAD.QuestionId
    LEFT JOIN
        PostLinkSummary PLS ON PEM.PostId = PLS.PostId
    LEFT JOIN
        CommentSummary CS ON PEM.PostId = CS.PostId
    WHERE
        (PEM.PostId IS NOT NULL AND PEM.PostScore >= -5 AND PEM.PostCreationDate BETWEEN DATE '2019-01-01' AND DATE '2023-12-31')
        OR (MHA.PostId IS NOT NULL AND COALESCE(MHA.NegativeModerationActions, 0) > 0)
)
SELECT
    PostId,
    PostTypeName,
    Title,
    PostScore,
    ViewCount,
    PostOwnerFinalDisplayName,
    PostOwnerReputation,
    PostCreationDate,
    LastActivityDate,
    PostHistoryCount,
    NegativeModerationActions,
    LastCloseReason,
    ContentAnalysisCategory,
    UserLocation,
    PrimaryTopicGroup,
    EngagementScoreMetric,
    TimeToAcceptance,
    UniqueUpVoters,
    ROW_NUMBER() OVER (PARTITION BY PostTypeName ORDER BY PostScore DESC, ViewCount DESC) AS RankWithinPostType,
    RANK() OVER (PARTITION BY PrimaryTopicGroup ORDER BY EngagementScoreMetric DESC NULLS LAST) AS RankByTopicEngagement,
    PERCENT_RANK() OVER (ORDER BY PostOwnerReputation DESC) AS OwnerReputationPercentile,
    LAG(PostScore, 1, 0) OVER (PARTITION BY PostOwnerFinalDisplayName ORDER BY PostCreationDate) AS PreviousPostScoreByOwner,
    NTILE(5) OVER (ORDER BY TimeSinceCreationActivity DESC) AS ActivityTimeQuintile
FROM
    MainPostAnalysis
WHERE
    PostId IS NOT NULL
    AND (
        ContentAnalysisCategory IN ('Highly Engaged Question', 'Top Accepted Answer')
        OR COALESCE(NegativeModerationActions, 0) > 0
        OR PostScore > 50
        OR ViewCount > 10000
    )
ORDER BY
    RankWithinPostType ASC, PostId DESC
LIMIT 1000;