-- {"query": "1661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3267} 

WITH UserContributionSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.UpVotes AS TotalUpvotesGiven,
        U.DownVotes AS TotalDownvotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsOwned,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersOwned,
        SUM(P.Score) AS TotalPostScoreReceived,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT PH_OwnedPost.PostId) AS TotalEditedOwnedPosts, -- Posts owned by U that have been edited by anyone
        SUM(CASE WHEN PH_Action.PostHistoryTypeId IN (10, 12) AND PH_Action.UserId = U.Id THEN 1 ELSE 0 END) AS PostsClosedOrDeletedByOwner, -- History types 10 (Post Closed), 12 (Post Deleted) by the owner
        SUM(CASE WHEN PH_Action.UserId = U.Id AND PH_Action.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS SelfEditsCount, -- Edit/Rollback Title/Body/Tags by self
        SUM(CASE WHEN VT.Name = 'UpMod' AND V.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalUpvotesByOthersOnMyPosts,
        SUM(CASE WHEN VT.Name = 'DownMod' AND V.UserId IS NOT NULL THEN 1 ELSE 0 END) AS TotalDownvotesByOthersOnMyPosts,
        MAX(P.Score) AS MaxSinglePostScore,
        MIN(P.Score) AS MinSinglePostScore
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH_OwnedPost ON P.Id = PH_OwnedPost.PostId AND PH_OwnedPost.PostHistoryTypeId IN (4, 5, 6) -- Any edit on posts owned by U
    LEFT JOIN PostHistory PH_Action ON U.Id = PH_Action.UserId -- Any history action performed by U
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Votes on posts owned by this user
    LEFT JOIN VoteTypes VT ON V.VoteTypeId = VT.Id
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
BadgeAndTagMetrics AS (
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        (SELECT COUNT(DISTINCT tag)
         FROM (SELECT TRIM(UNNEST(string_to_array(SUBSTRING(P_Inner.Tags, 2, LENGTH(P_Inner.Tags) - 2), '><'))) AS tag
               FROM Posts P_Inner
               WHERE P_Inner.OwnerUserId = U.Id AND P_Inner.Tags IS NOT NULL AND P_Inner.PostTypeId IN (1, 2)
              ) AS UserTagsList
        ) AS DistinctTagsFromOwnedPosts -- Correlated subquery for distinct tags per user
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    GROUP BY U.Id
),
PostSpecificAnalysis AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.LastActivityDate AS PostLastActivityDate,
        P.ViewCount,
        P.Score AS PostScore,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        COALESCE(P.ClosedDate, '1900-01-01 00:00:00'::timestamp) AS PostClosedDate, -- Handle NULL for ClosedDate
        (SELECT COUNT(PH2.Id) FROM PostHistory PH2 WHERE PH2.PostId = P.Id AND PH2.PostHistoryTypeId IN (4, 5, 6)) AS TotalMinorEditsByAnyone, -- Edits (Title, Body, Tags)
        (SELECT
            CAST(EXTRACT(EPOCH FROM (MIN(A.CreationDate) - P.CreationDate)) / 60.0 AS NUMERIC(10, 2)) -- Time to first answer in minutes
         FROM Posts A
         WHERE A.ParentId = P.Id AND A.PostTypeId = 2
         GROUP BY P.Id
        ) AS TimeToFirstAnswerMinutes,
        COALESCE(SUM(C.Score), 0) AS TotalCommentScoreOnPost,
        CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        CASE WHEN P.CommunityOwnedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsCommunityOwned,
        LENGTH(P.Body) AS PostBodyLength,
        LENGTH(P.Title) AS PostTitleLength,
        ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS TagCountForPost -- Number of tags for the post
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId
    WHERE P.OwnerUserId IS NOT NULL -- Exclude community user posts for user-centric analysis
    GROUP BY P.Id, P.OwnerUserId, P.CreationDate, P.LastActivityDate, P.ViewCount, P.Score, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.ClosedDate, P.PostTypeId, P.AcceptedAnswerId, P.CommunityOwnedDate, P.Body, P.Title, P.Tags
)
-- Main query combining all CTEs
SELECT
    U.Id AS UserId,
    COALESCE(U.DisplayName, 'Deleted User (' || U.Id || ')') AS DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate AS UserLastAccessDate,
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - U.CreationDate)) AS UserAccountAgeDays,
    UCS.TotalPostsOwned,
    UCS.TotalQuestionsOwned,
    UCS.TotalAnswersOwned,
    UCS.TotalCommentsMade,
    UCS.TotalUpvotesGiven,
    UCS.TotalDownvotesGiven,
    UCS.TotalPostScoreReceived,
    UCS.TotalUpvotesByOthersOnMyPosts,
    UCS.TotalDownvotesByOthersOnMyPosts,
    CAST(COALESCE(UCS.TotalPostScoreReceived, 0) AS NUMERIC(10,2)) / NULLIF(UCS.TotalPostsOwned, 0) AS AvgScorePerOwnedPost,
    CAST(COALESCE(UCS.TotalDownvotesByOthersOnMyPosts, 0) AS NUMERIC(10,2)) / NULLIF(COALESCE(UCS.TotalUpvotesByOthersOnMyPosts, 0) + COALESCE(UCS.TotalDownvotesByOthersOnMyPosts, 0), 0) AS DownvoteRatioOnPosts,
    UCS.SelfEditsCount,
    UCS.PostsClosedOrDeletedByOwner,
    BTM.TotalBadges,
    BTM.GoldBadges,
    BTM.SilverBadges,
    BTM.BronzeBadges,
    BTM.DistinctTagsFromOwnedPosts,
    -- Window functions: Rank users by reputation and total posts
    RANK() OVER (ORDER BY U.Reputation DESC, COALESCE(UCS.TotalPostsOwned, 0) DESC) AS GlobalReputationRank,
    NTILE(10) OVER (ORDER BY U.Reputation DESC) AS ReputationDecile, -- Which 10% bracket the user falls into by reputation
    -- Aggregate post-specific metrics
    COALESCE(SUM(PSA.ViewCount), 0) AS TotalViewCountOnOwnedPosts,
    COALESCE(SUM(PSA.FavoriteCount), 0) AS TotalFavoriteCountOnOwnedPosts,
    COALESCE(AVG(PSA.TotalMinorEditsByAnyone) FILTER (WHERE PSA.TotalMinorEditsByAnyone IS NOT NULL), 0) AS AvgEditsPerOwnedPost,
    COALESCE(AVG(PSA.TimeToFirstAnswerMinutes) FILTER (WHERE PSA.TimeToFirstAnswerMinutes IS NOT NULL), 0) AS AvgTimeToFirstAnswerForQuestions,
    MAX(CASE WHEN PSA.HasAcceptedAnswer THEN 1 ELSE 0 END) AS HasAnyAcceptedAnswer, -- If at least one of their questions has an accepted answer
    MAX(CASE WHEN PSA.IsCommunityOwned THEN 1 ELSE 0 END) AS HasAnyCommunityOwnedPost,
    COALESCE(AVG(PSA.PostBodyLength) FILTER (WHERE PSA.PostBodyLength IS NOT NULL), 0) AS AvgOwnedPostBodyLength,
    COALESCE(AVG(PSA.PostTitleLength) FILTER (WHERE PSA.PostTitleLength IS NOT NULL), 0) AS AvgOwnedPostTitleLength,
    MAX(PSA.PostClosedDate) AS LatestPostClosedDate,
    -- Correlated subquery to find posts with highest comment scores for this user
    (SELECT P_TOP.Title FROM Posts P_TOP WHERE P_TOP.OwnerUserId = U.Id ORDER BY (SELECT COALESCE(SUM(C_TOP.Score),0) FROM Comments C_TOP WHERE C_TOP.PostId = P_TOP.Id) DESC, P_TOP.CreationDate DESC LIMIT 1) AS TopPostByCommentScoreTitle,
    -- Subquery to find the most used tag by this user
    (SELECT TagName FROM (
        SELECT
            TRIM(UNNEST(string_to_array(SUBSTRING(p_tags.Tags, 2, LENGTH(p_tags.Tags) - 2), '><'))) AS TagName,
            COUNT(*) AS TagUsageCount
        FROM Posts p_tags
        WHERE p_tags.OwnerUserId = U.Id AND p_tags.Tags IS NOT NULL
        GROUP BY 1
        ORDER BY TagUsageCount DESC
        LIMIT 1
    ) AS MostUsedTag) AS MostUsedTagByOwner,
    U.WebsiteUrl,
    U.Location,
    U.AboutMe,
    LENGTH(U.AboutMe) AS AboutMeLength,
    -- String expressions
    CASE
        WHEN U.AboutMe IS NOT NULL AND (U.AboutMe LIKE '%<a href="http://%' OR U.AboutMe LIKE '%<a href="https://%') THEN TRUE
        ELSE FALSE
    END AS HasWebsiteLinkInAboutMe,
    -- NULL logic and complex predicate
    CASE
        WHEN U.Reputation > 5000 AND COALESCE(UCS.TotalAnswersOwned, 0) > 50 AND COALESCE(BTM.GoldBadges, 0) > 0 AND COALESCE(UCS.SelfEditsCount, 0) > 10 AND COALESCE(CAST(UCS.TotalDownvotesByOthersOnMyPosts AS NUMERIC) / NULLIF(COALESCE(UCS.TotalUpvotesByOthersOnMyPosts, 0) + COALESCE(UCS.TotalDownvotesByOthersOnMyPosts, 0), 0), 0) > 0.1 THEN 'High Engagement & Potentially Controversial'
        WHEN U.Reputation > 1000 AND COALESCE(UCS.TotalQuestionsOwned, 0) > 20 AND COALESCE(BTM.DistinctTagsFromOwnedPosts, 0) > 5 THEN 'Active Questioner with Diverse Interests'
        WHEN U.CreationDate > (CURRENT_TIMESTAMP - INTERVAL '1 year') AND COALESCE(UCS.TotalPostsOwned, 0) > 10 AND COALESCE(CAST(UCS.TotalPostScoreReceived AS NUMERIC) / NULLIF(UCS.TotalPostsOwned, 0), 0) > 5 THEN 'Promising New Contributor'
        ELSE 'Other Contributor Type'
    END AS UserEngagementProfileCategory
FROM Users U
LEFT JOIN UserContributionSummary UCS ON U.Id = UCS.UserId
LEFT JOIN BadgeAndTagMetrics BTM ON U.Id = BTM.UserId
LEFT JOIN PostSpecificAnalysis PSA ON U.Id = PSA.OwnerUserId
WHERE
    U.Reputation >= 100 -- Focus on users with some reputation
    AND U.LastAccessDate IS NOT NULL -- Users who have accessed recently
    AND U.Views >= 50 -- Users who have been viewed a decent amount
    AND U.AboutMe IS NOT NULL -- To enable string operations on AboutMe
GROUP BY
    U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes,
    UCS.TotalPostsOwned, UCS.TotalQuestionsOwned, UCS.TotalAnswersOwned, UCS.TotalCommentsMade,
    UCS.TotalUpvotesGiven, UCS.TotalDownvotesGiven, UCS.TotalPostScoreReceived,
    UCS.TotalUpvotesByOthersOnMyPosts, UCS.TotalDownvotesByOthersOnMyPosts,
    UCS.SelfEditsCount, UCS.PostsClosedOrDeletedByOwner,
    BTM.TotalBadges, BTM.GoldBadges, BTM.SilverBadges, BTM.BronzeBadges, BTM.DistinctTagsFromOwnedPosts,
    U.WebsiteUrl, U.Location, U.AboutMe
HAVING
    COUNT(PSA.PostId) > 0 -- Ensure the user owns at least one post for post-level aggregations to be meaningful
    OR COALESCE(UCS.TotalPostsOwned, 0) > 0 -- Fallback if PSA join results in no records due to filtering within PSA
ORDER BY
    U.Reputation DESC, UserAccountAgeDays DESC
LIMIT 1000;
