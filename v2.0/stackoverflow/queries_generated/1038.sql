-- {"query": "1038.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3313} 
WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (60*60*24) AS UserTenureDays,
        COALESCE(U.Views, 0) AS TotalProfileViews,
        U.UpVotes AS TotalGivenUpVotes,
        U.DownVotes AS TotalGivenDownVotes,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(P.Score) AS TotalPostScore,
        SUM(P.ViewCount) AS TotalPostViewCount,
        SUM(CASE WHEN P.PostTypeId = 1 THEN P.AnswerCount ELSE 0 END) AS TotalAnswersReceived,
        SUM(P.CommentCount) AS TotalCommentsOnPosts,
        SUM(P.FavoriteCount) AS TotalFavoriteCounts,
        MAX(P.CreationDate) AS LastPostDate,
        MAX(C.CreationDate) AS LastCommentDate,
        STRING_AGG(DISTINCT SUBSTRING(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')), 1, 30), ';') FILTER (WHERE P.Tags IS NOT NULL) AS DominantTags_Concat
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostDetailsAggregated AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.CreationDate AS PostCreationDate,
        P.LastEditDate,
        P.ClosedDate,
        P.ParentId,
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT MAX(PH_Edit.CreationDate) FROM PostHistory PH_Edit WHERE PH_Edit.PostId = P.Id AND PH_Edit.PostHistoryTypeId IN (4, 5, 6)) AS LastEditHistoryDate,
        COUNT(DISTINCT V_Up.Id) AS UpVoteCount,
        COUNT(DISTINCT V_Down.Id) AS DownVoteCount,
        COUNT(DISTINCT V_Fav.Id) AS FavoriteVoteCount,
        (SELECT T.TagName FROM Tags T WHERE P.Tags LIKE '%' || T.TagName || '%' ORDER BY T.Count DESC LIMIT 1) AS PrimaryTag,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        COALESCE(LENGTH(P.Body), 0) AS BodyLength,
        COALESCE(LENGTH(P.Title), 0) AS TitleLength
    FROM Posts P
    LEFT JOIN Votes V_Up ON P.Id = V_Up.PostId AND V_Up.VoteTypeId = 2 -- UpMod
    LEFT JOIN Votes V_Down ON P.Id = V_Down.PostId AND V_Down.VoteTypeId = 3 -- DownMod
    LEFT JOIN Votes V_Fav ON P.Id = V_Fav.PostId AND V_Fav.VoteTypeId = 5 -- Favorite (bookmark)
    GROUP BY P.Id, P.OwnerUserId, P.PostTypeId, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.CreationDate, P.LastEditDate, P.ClosedDate, P.ParentId, P.AcceptedAnswerId, P.Body, P.Title, P.Tags
),
UserPostMetrics AS (
    SELECT
        PDA.OwnerUserId AS UserId,
        COUNT(PDA.PostId) AS UserTotalPosts,
        SUM(PDA.Score) AS UserTotalPostScore,
        SUM(PDA.ViewCount) AS UserTotalPostViews,
        AVG(PDA.EditCount) AS AverageEditCountPerPost,
        MAX(CASE WHEN PDA.HasAcceptedAnswer THEN 1 ELSE 0 END) AS HasEverAcceptedAnswer, -- User owns a question with accepted answer
        SUM(CASE WHEN PDA.PostTypeId = 1 AND PDA.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS UserTotalClosedQuestions,
        SUM(CASE WHEN PDA.PostTypeId = 2 AND PDA.PostId = PDA_Parent.AcceptedAnswerId THEN 1 ELSE 0 END) AS UserTotalAcceptedAnswersGiven,
        SUM(PDA.UpVoteCount) AS UserTotalPostUpVotes,
        SUM(PDA.DownVoteCount) AS UserTotalPostDownVotes,
        AVG(CASE WHEN PDA.UpVoteCount + PDA.DownVoteCount > 0 THEN PDA.UpVoteCount::numeric / (PDA.UpVoteCount + PDA.DownVoteCount) ELSE 0 END) AS AveragePostUpVoteRatio,
        COUNT(DISTINCT PDA.PrimaryTag) AS UniqueTagsPosted,
        SUM(CASE WHEN PDA.BodyLength > 1000 THEN 1 ELSE 0 END) AS LongPostsCount
    FROM PostDetailsAggregated PDA
    LEFT JOIN Posts PDA_Parent ON PDA.ParentId = PDA_Parent.Id
    GROUP BY PDA.OwnerUserId
),
BadgeAchievement AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        COUNT(CASE WHEN B.TagBased = TRUE THEN B.Id END) AS TagBasedBadges
    FROM Badges B
    GROUP BY B.UserId
),
PostLinkContribution AS (
    -- User's posts that link to other posts
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PL.PostId) AS OwnPostsLinkingOut,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS OwnPostsReferencingDuplicates
    FROM Posts P
    JOIN PostLinks PL ON P.Id = PL.PostId
    GROUP BY P.OwnerUserId
    UNION ALL
    -- User's posts that are linked to by other posts, or marked as duplicates
    SELECT
        P.OwnerUserId AS UserId,
        0 AS OwnPostsLinkingOut,
        COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.PostId END) AS OwnPostsReferencedAsDuplicates
    FROM Posts P
    JOIN PostLinks PL ON P.Id = PL.RelatedPostId
    GROUP BY P.OwnerUserId
),
UserLinkSummary AS (
    SELECT
        UserId,
        SUM(OwnPostsLinkingOut) AS TotalOwnPostsLinkingOut,
        SUM(OwnPostsReferencingDuplicates) AS TotalOwnPostsReferencingDuplicates,
        SUM(OwnPostsReferencedAsDuplicates) AS TotalOwnPostsReferencedAsDuplicates
    FROM PostLinkContribution
    GROUP BY UserId
),
UserEngagementRank AS (
    SELECT
        UAS.UserId,
        UAS.Reputation,
        UAS.UserTenureDays,
        UAS.TotalPosts,
        UAS.TotalComments,
        UPM.UserTotalPostScore,
        UPM.UserTotalPostViews,
        UPM.AverageEditCountPerPost,
        UPM.UserTotalClosedQuestions,
        UPM.UserTotalAcceptedAnswersGiven,
        UPM.AveragePostUpVoteRatio,
        BA.TotalBadges,
        BA.GoldBadges,
        BA.SilverBadges,
        BA.BronzeBadges,
        ULS.TotalOwnPostsLinkingOut,
        ULS.TotalOwnPostsReferencingDuplicates,
        ULS.TotalOwnPostsReferencedAsDuplicates,
        UAS.DominantTags_Concat,
        RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPosts DESC, UPM.UserTotalPostScore DESC) AS OverallRank,
        NTILE(10) OVER (ORDER BY UAS.Reputation DESC) AS ReputationDecile,
        AVG(UPM.AveragePostUpVoteRatio) OVER (ORDER BY UAS.Reputation ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS AvgUpVoteRatio_Smooth,
        LAG(UAS.LastAccessDate, 1, UAS.CreationDate) OVER (PARTITION BY UAS.UserId ORDER BY UAS.LastAccessDate) AS PreviousLastAccessDate, -- Dummy example for LAG, as it's not truly sequential here per user.
        COUNT(DISTINCT P_Closed.Id) OVER (PARTITION BY UAS.UserId) AS UserSpecificClosedPostCount
    FROM UserActivitySummary UAS
    LEFT JOIN UserPostMetrics UPM ON UAS.UserId = UPM.UserId
    LEFT JOIN BadgeAchievement BA ON UAS.UserId = BA.UserId
    LEFT JOIN UserLinkSummary ULS ON UAS.UserId = ULS.UserId
    LEFT JOIN Posts P_Closed ON UAS.UserId = P_Closed.OwnerUserId AND P_Closed.ClosedDate IS NOT NULL
)
SELECT
    UER.UserId,
    U.DisplayName,
    UER.Reputation,
    UER.UserTenureDays,
    UER.TotalPosts,
    UER.TotalComments,
    UER.UserTotalPostScore,
    UER.UserTotalPostViews,
    UER.AverageEditCountPerPost,
    UER.UserTotalClosedQuestions,
    UER.UserTotalAcceptedAnswersGiven,
    UER.TotalBadges,
    UER.GoldBadges,
    UER.SilverBadges,
    UER.BronzeBadges,
    UER.DominantTags_Concat,
    UER.OverallRank,
    UER.ReputationDecile,
    UER.AvgUpVoteRatio_Smooth,
    UER.TotalOwnPostsLinkingOut,
    UER.TotalOwnPostsReferencedAsDuplicates,
    -- Correlated subquery example: get the average score of the user's top 3 most viewed posts
    (
        SELECT COALESCE(AVG(SubP.Score), 0)
        FROM (
            SELECT P_Inner.Score
            FROM Posts P_Inner
            WHERE P_Inner.OwnerUserId = UER.UserId
            ORDER BY P_Inner.ViewCount DESC, P_Inner.Score DESC
            LIMIT 3
        ) AS SubP
    ) AS AvgTop3ViewedPostScore,
    -- Another correlated subquery: check if user has ever posted in a 'hot' tag (e.g., tags with > 1000 posts and avg score > 5)
    EXISTS (
        SELECT 1
        FROM Posts P_Hot
        JOIN Tags T_Hot ON P_Hot.Tags LIKE '%' || T_Hot.TagName || '%'
        WHERE P_Hot.OwnerUserId = UER.UserId
        AND T_Hot.Count > 1000
        AND (SELECT COALESCE(AVG(P_TagAvg.Score), 0) FROM Posts P_TagAvg WHERE P_TagAvg.Tags LIKE '%' || T_Hot.TagName || '%') > 5
        LIMIT 1
    ) AS HasPostedInHotTag,
    -- Complicated string expression for a hypothetical 'reputation tier' based on about me length
    CASE
        WHEN U.AboutMe IS NULL OR LENGTH(U.AboutMe) < 50 THEN 'Low-Detail Bio'
        WHEN LENGTH(U.AboutMe) BETWEEN 50 AND 200 THEN 'Mid-Detail Bio'
        WHEN LENGTH(U.AboutMe) > 200 AND U.Reputation > 5000 THEN 'High-Rep Detailed Bio'
        WHEN LENGTH(U.AboutMe) > 200 AND U.Reputation <= 5000 THEN 'Standard Detailed Bio'
        ELSE 'Unknown Bio Tier'
    END AS BioReputationTier,
    COALESCE(U.Location, 'N/A') AS UserLocation,
    CASE
        WHEN UER.Reputation > 10000 AND UER.GoldBadges >= 3 THEN 'Elite Contributor'
        WHEN UER.Reputation > 2000 AND UER.TotalPosts > 50 THEN 'Active Expert'
        WHEN UER.Reputation > 500 AND UER.TotalComments > 100 THEN 'Engaged Commenter'
        ELSE 'General Participant'
    END AS UserCategory,
    (UER.Reputation * 0.1 + COALESCE(UER.UserTotalPostScore, 0) * 0.5 + COALESCE(UER.TotalBadges, 0) * 1.5 - COALESCE(UER.UserTotalClosedQuestions, 0) * 2.0)
    / GREATEST(UER.UserTenureDays, 1, 0.0001) AS WeightedEngagementPerDay, -- Use 0.0001 to prevent division by zero for new users
    EXTRACT(YEAR FROM U.CreationDate) AS UserCreationYear,
    COALESCE(U.AboutMe, '') ILIKE '%database%' AS IsDatabaseUser_AboutMe,
    COALESCE(U.AboutMe, '') ILIKE '%sql%' AS IsSQLUser_AboutMe
FROM UserEngagementRank UER
JOIN Users U ON UER.UserId = U.Id
WHERE
    UER.Reputation >= 1000
    AND UER.TotalPosts > 10
    AND UER.ReputationDecile <= 5 -- Focus on top 50% by reputation
    AND (UER.DominantTags_Concat LIKE '%<sql>%' OR UER.DominantTags_Concat LIKE '%<database>%') -- String search in concatenated tags
ORDER BY
    UER.Reputation DESC, UER.UserTotalPostScore DESC
LIMIT 100;