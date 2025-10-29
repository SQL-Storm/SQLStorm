WITH ParsedPostTags AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')) AS TagName
    FROM Posts P
    WHERE P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
      AND P.PostTypeId = 1
),
PostCommentEditAggregates AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.AcceptedAnswerId,
        COALESCE(P.CommunityOwnedDate, TIMESTAMP '1900-01-01') AS CommunityOwnedDate,
        COALESCE(P.ParentId, -1) AS ParentPostId,
        COUNT(DISTINCT C.Id) AS TotalCommentsOnPost,
        MAX(C.CreationDate) AS LatestCommentDateOnPost,
        COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS TotalEditRevisions,
        MAX(PH.CreationDate) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)) AS LatestEditDate
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.PostTypeId IN (1, 2)
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.FavoriteCount, P.ClosedDate, P.AcceptedAnswerId, P.CommunityOwnedDate, P.ParentId
),
PostTagsAndLinks AS (
    SELECT
        PCA.PostId,
        STRING_AGG(DISTINCT PPT.TagName, '$$$') FILTER (WHERE PPT.TagName IS NOT NULL) AS AssociatedTagsString,
        COUNT(DISTINCT PL_Linked.RelatedPostId) FILTER (WHERE PL_Linked.LinkTypeId = 1) AS CountLinkedToPosts,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) FILTER (WHERE PL_Duplicate.LinkTypeId = 3) AS CountDuplicateOfPosts
    FROM PostCommentEditAggregates PCA
    LEFT JOIN ParsedPostTags PPT ON PCA.PostId = PPT.PostId
    LEFT JOIN PostLinks PL_Linked ON PCA.PostId = PL_Linked.PostId
    LEFT JOIN PostLinks PL_Duplicate ON PCA.PostId = PL_Duplicate.PostId
    GROUP BY PCA.PostId
),
CombinedPostMetrics AS (
    SELECT
        PCA.PostId,
        PCA.OwnerUserId,
        PCA.PostTypeId,
        PCA.PostCreationDate,
        PCA.PostScore,
        PCA.PostViewCount,
        PCA.AnswerCount,
        PCA.FavoriteCount,
        PCA.ClosedDate,
        PCA.AcceptedAnswerId,
        PCA.CommunityOwnedDate,
        PCA.ParentPostId,
        PCA.TotalCommentsOnPost,
        PCA.LatestCommentDateOnPost,
        PCA.TotalEditRevisions,
        PCA.LatestEditDate,
        PTL.AssociatedTagsString,
        PTL.CountLinkedToPosts,
        PTL.CountDuplicateOfPosts,
        (PCA.PostScore * 0.5 + PCA.PostViewCount * 0.01 + PCA.TotalCommentsOnPost * 2 + COALESCE(PCA.FavoriteCount, 0) * 5 + COALESCE(PCA.AnswerCount, 0) * 3 + PCA.TotalEditRevisions * -1) AS PostEngagementScore,
        CASE
            WHEN PCA.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN PCA.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswer'
            WHEN PCA.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'OpenNoAnswers'
        END AS DerivedPostStatus,
        AGE(TIMESTAMP '2024-10-01 12:34:56', PCA.PostCreationDate) AS PostAgeInterval,
        (SELECT AVG(CAST(A.Score AS NUMERIC)) FROM Posts A WHERE A.ParentId = PCA.PostId AND PCA.PostTypeId = 1) AS AvgAnswerScoreForQuestion
    FROM PostCommentEditAggregates PCA
    LEFT JOIN PostTagsAndLinks PTL ON PCA.PostId = PTL.PostId
),
UserOverallMetrics AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUserUpvotesGiven,
        U.DownVotes AS TotalUserDownvotesGiven,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        CASE WHEN U.WebsiteUrl IS NOT NULL THEN TRUE ELSE FALSE END AS HasWebsite,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        MAX(B.Date) AS LatestBadgeDate,
        COUNT(DISTINCT CASE WHEN CPM.PostTypeId = 1 THEN CPM.PostId END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN CPM.PostTypeId = 2 THEN CPM.PostId END) AS TotalAnswersProvided,
        COUNT(DISTINCT CPM.PostId) AS TotalPostsContributed,
        COALESCE(SUM(CPM.PostScore), 0) AS TotalPostsScore,
        COALESCE(SUM(CPM.PostViewCount), 0) AS TotalPostsViewCount,
        COALESCE(SUM(CPM.FavoriteCount), 0) AS TotalPostsFavoriteCount,
        COALESCE(SUM(CPM.TotalCommentsOnPost), 0) AS TotalCommentsOnOwnPosts,
        COALESCE(AVG(CPM.PostEngagementScore), 0.0) AS AvgPostEngagementScore,
        COALESCE(AVG(NULLIF(CASE WHEN CPM.PostTypeId = 1 THEN CPM.AnswerCount END, 0)), 0.0) AS AvgAnswersPerQuestion,
        COALESCE(CAST(SUM(CASE WHEN CPM.PostTypeId = 1 AND CPM.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN CPM.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 0.0) AS QuestionAcceptanceRate,
        COALESCE(CAST(SUM(CASE WHEN CPM.PostTypeId = 2 AND P_PARENT.AcceptedAnswerId = CPM.PostId THEN 1 ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN CPM.PostTypeId = 2 THEN 1 ELSE 0 END), 0), 0.0) AS AnswerAcceptanceRate,
        MAX(CPM.LatestEditDate) AS LatestContentEditDate,
        SUM(CASE WHEN CPM.DerivedPostStatus = 'Closed' THEN 1 ELSE 0 END) AS ClosedPostsCount,
        STRING_AGG(DISTINCT SUBSTRING(CPM.AssociatedTagsString FROM 1 FOR 50) || '...', ' | ') FILTER (WHERE CPM.AssociatedTagsString IS NOT NULL AND CPM.AssociatedTagsString <> '') AS TopTagsExcerpt,
        MIN(CASE WHEN rn_top = 1 THEN CPM.PostId END) AS TopScoringPostId,
        MIN(CASE WHEN rn_top = 1 THEN CPM.PostScore END) AS TopScoringPostScore,
        (SELECT AVG(CAST(U2.Reputation AS NUMERIC)) FROM Users U2 WHERE U2.CreationDate BETWEEN U.CreationDate - INTERVAL '6 months' AND U.CreationDate + INTERVAL '6 months') AS AvgReputationOfContemporaries
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN (
        SELECT
            CPM.*,
            ROW_NUMBER() OVER (PARTITION BY CPM.OwnerUserId ORDER BY CPM.PostScore DESC, CPM.PostCreationDate DESC) AS rn_top
        FROM CombinedPostMetrics CPM
    ) CPM ON U.Id = CPM.OwnerUserId
    LEFT JOIN Posts P_PARENT ON CPM.ParentPostId = P_PARENT.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes, U.Location, U.WebsiteUrl
),
FinalUserRanking AS (
    SELECT
        UOM.UserId,
        UOM.DisplayName,
        UOM.Reputation,
        UOM.UserLocation,
        UOM.TotalBadges,
        UOM.GoldBadges,
        UOM.TotalQuestionsAsked,
        UOM.TotalAnswersProvided,
        UOM.TotalPostsContributed,
        UOM.TotalPostsScore,
        UOM.AvgPostEngagementScore,
        UOM.QuestionAcceptanceRate,
        UOM.AnswerAcceptanceRate,
        UOM.ClosedPostsCount,
        NULLIF(UOM.TopTagsExcerpt, '...') AS TopTagsSummary,
        UOM.TopScoringPostId,
        UOM.TopScoringPostScore,
        UOM.AvgReputationOfContemporaries,
        RANK() OVER (ORDER BY UOM.Reputation DESC, UOM.TotalPostsScore DESC, UOM.AvgPostEngagementScore DESC, UOM.AnswerAcceptanceRate DESC) AS OverallUserRank,
        NTILE(5) OVER (ORDER BY UOM.Reputation DESC) AS ReputationQuintile,
        LAG(UOM.DisplayName, 1, '---') OVER (ORDER BY UOM.Reputation DESC) AS PreviousRankedUser,
        LEAD(UOM.DisplayName, 1, '---') OVER (ORDER BY UOM.Reputation DESC) AS NextRankedUser,
        COALESCE(UPPER(SUBSTRING(UOM.DisplayName FROM 1 FOR 1)), '?') || '-' || COALESCE(UOM.UserLocation, 'UNKNOWN') || '-' || LPAD(CAST(UOM.UserId AS TEXT), 8, '0') AS UserIdentifierString,
        CASE
            WHEN UOM.Reputation >= 10000 AND UOM.GoldBadges >= 5 THEN 'Legendary Contributor'
            WHEN UOM.Reputation >= 5000 OR UOM.TotalPostsContributed >= 500 THEN 'Prodigious Contributor'
            WHEN UOM.Reputation >= 1000 AND UOM.TotalPostsScore >= 1000 AND UOM.QuestionAcceptanceRate >= 0.5 THEN 'Active & Effective Contributor'
            WHEN UOM.TotalPostsContributed > 100 AND UOM.TotalPostsScore > 500 AND UOM.AnswerAcceptanceRate > 0.6 THEN 'Specialized Answerer'
            ELSE 'Casual User'
        END AS UserContributionTier
    FROM UserOverallMetrics UOM
    WHERE UOM.TotalPostsContributed > 10
      AND UOM.Reputation IS NOT NULL
)
SELECT *
FROM FinalUserRanking;