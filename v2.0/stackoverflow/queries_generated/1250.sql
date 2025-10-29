-- {"query": "1250.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 4396} 

WITH UserActivitySummary AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersGiven,
        SUM(P.Score) AS TotalPostScore,
        AVG(P.Score) AS AvgPostScore,
        SUM(P.ViewCount) AS TotalPostViews,
        MAX(P.CreationDate) AS LatestPostCreation,
        MIN(P.CreationDate) AS EarliestPostCreation
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
CommentContribution AS (
    SELECT
        C.UserId,
        COUNT(C.Id) AS TotalComments,
        SUM(C.Score) AS TotalCommentScore,
        MAX(C.CreationDate) AS LatestCommentCreation
    FROM Comments C
    WHERE C.UserId IS NOT NULL
    GROUP BY C.UserId
),
PostEditAndCloseStats AS (
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(PH_Edit.Id) AS TotalEditsMadeByUsersPosts, -- Edits on posts owned by the user
        COUNT(CASE WHEN PH_Close.PostHistoryTypeId = 10 THEN PH_Close.PostId END) AS UserPostsClosedCount,
        COUNT(CASE WHEN PH_Reopen.PostHistoryTypeId = 11 THEN PH_Reopen.PostId END) AS UserPostsReopenedCount,
        COUNT(CASE WHEN PH_Delete.PostHistoryTypeId = 12 THEN PH_Delete.PostId END) AS UserPostsDeletedCount,
        COUNT(CASE WHEN PH_MigrateAway.PostHistoryTypeId = 35 THEN PH_MigrateAway.PostId END) AS UserPostsMigratedAway
    FROM Posts P
    LEFT JOIN PostHistory PH_Edit ON P.Id = PH_Edit.PostId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostHistory PH_Close ON P.Id = PH_Close.PostId AND PH_Close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory PH_Reopen ON P.Id = PH_Reopen.PostId AND PH_Reopen.PostHistoryTypeId = 11
    LEFT JOIN PostHistory PH_Delete ON P.Id = PH_Delete.PostId AND PH_Delete.PostHistoryTypeId = 12
    LEFT JOIN PostHistory PH_MigrateAway ON P.Id = PH_MigrateAway.PostId AND PH_MigrateAway.PostHistoryTypeId = 35
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
BadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LatestBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
UserVoteInfluence AS (
    SELECT
        V.UserId,
        COUNT(V.Id) AS TotalVotesCast,
        COUNT(CASE WHEN V.VoteTypeId = 2 THEN V.Id END) AS UpvotesCast,
        COUNT(CASE WHEN V.VoteTypeId = 3 THEN V.Id END) AS DownvotesCast,
        COUNT(CASE WHEN V.VoteTypeId = 6 THEN V.Id END) AS CloseVotesCast, -- Old close votes
        COUNT(CASE WHEN V.VoteTypeId = 10 THEN V.Id END) AS DeletionVotesCast,
        MAX(V.CreationDate) AS LatestVoteCastDate
    FROM Votes V
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
),
TopTagsByOwner AS (
    SELECT
        P.OwnerUserId AS UserId,
        T.TagName,
        COUNT(P.Id) AS TagPostCount,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY COUNT(P.Id) DESC, T.TagName) AS rn
    FROM Posts P
    JOIN LATERAL UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS tag_name ON TRUE
    JOIN Tags T ON tag_name = T.TagName
    WHERE P.PostTypeId = 1 AND P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    GROUP BY P.OwnerUserId, T.TagName
),
UserTopTag AS (
    SELECT
        UserId,
        TopTagName
    FROM TopTagsByOwner
    WHERE rn = 1
),
ActiveUsers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        LENGTH(U.AboutMe) AS AboutMeLength,
        COALESCE(U.Views, 0) AS UserProfileViews,
        COALESCE(U.UpVotes, 0) AS UserGivenUpvotes,
        COALESCE(U.DownVotes, 0) AS UserGivenDownvotes,
        COALESCE(UAS.TotalPosts, 0) AS TotalPosts,
        COALESCE(UAS.QuestionsAsked, 0) AS QuestionsAsked,
        COALESCE(UAS.AnswersGiven, 0) AS AnswersGiven,
        COALESCE(UAS.TotalPostScore, 0) AS TotalPostScore,
        COALESCE(UAS.AvgPostScore, 0.0) AS AvgPostScore,
        COALESCE(CC.TotalComments, 0) AS TotalComments,
        COALESCE(CC.TotalCommentScore, 0) AS TotalCommentScore,
        COALESCE(PES.TotalEditsMadeByUsersPosts, 0) AS TotalPostEdits,
        COALESCE(PES.UserPostsClosedCount, 0) AS UserPostsClosedCount,
        COALESCE(BS.TotalBadges, 0) AS TotalBadges,
        COALESCE(BS.GoldBadges, 0) AS GoldBadges,
        COALESCE(BS.SilverBadges, 0) AS SilverBadges,
        COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(UVI.UpvotesCast, 0) AS UpvotesCast,
        COALESCE(UVI.DownvotesCast, 0) AS DownvotesCast,
        COALESCE(UTT.TopTagName, 'N/A') AS MostFrequentTag,
        (U.Reputation * 0.5 + COALESCE(UAS.TotalPostScore, 0) * 0.3 + COALESCE(BS.GoldBadges, 0) * 10 + COALESCE(BS.SilverBadges, 0) * 5 + COALESCE(BS.BronzeBadges, 0) * 1) AS UserEngagementScore,
        RANK() OVER (ORDER BY (U.Reputation + COALESCE(UAS.TotalPostScore, 0)) DESC, U.LastAccessDate DESC) AS OverallRank,
        LAG(U.Reputation, 1, 0) OVER (ORDER BY U.CreationDate) AS PrevUserReputation,
        (SELECT COUNT(DISTINCT P_sub.Id) FROM Posts P_sub WHERE P_sub.OwnerUserId = U.Id AND P_sub.PostTypeId = 1 AND P_sub.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswersForOwnQuestions,
        CASE
            WHEN U.Location LIKE '%United States%' OR U.Location LIKE '%USA%' THEN 'North America'
            WHEN U.Location LIKE '%Canada%' THEN 'North America'
            WHEN U.Location LIKE '%UK%' OR U.Location LIKE '%United Kingdom%' THEN 'Europe'
            WHEN U.Location LIKE '%India%' THEN 'Asia'
            ELSE 'Other'
        END AS ContinentGroup
    FROM Users U
    LEFT JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
    LEFT JOIN CommentContribution CC ON U.Id = CC.UserId
    LEFT JOIN PostEditAndCloseStats PES ON U.Id = PES.UserId
    LEFT JOIN BadgeSummary BS ON U.Id = BS.UserId
    LEFT JOIN UserVoteInfluence UVI ON U.Id = UVI.UserId
    LEFT JOIN UserTopTag UTT ON U.Id = UTT.UserId
    WHERE U.Reputation >= 1000
      AND (U.LastAccessDate >= CURRENT_DATE - INTERVAL '1 year' OR UAS.LatestPostCreation >= CURRENT_DATE - INTERVAL '1 year')
      AND (U.DisplayName IS NOT NULL AND U.DisplayName <> '')
      AND U.AccountId IS NOT NULL
),
ModeratorInfluencedPosts AS (
    SELECT
        PH.UserId AS ModeratorId,
        U.DisplayName AS ModeratorDisplayName,
        PH.PostId,
        PH.PostHistoryTypeId,
        P.PostTypeId,
        PH.CreationDate AS EventDate,
        CRT.Name AS CloseReason,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate DESC) AS rn_latest_event
    FROM PostHistory PH
    JOIN Users U ON PH.UserId = U.Id
    JOIN Posts P ON PH.PostId = P.Id
    LEFT JOIN CloseReasonTypes CRT ON PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL AND CRT.Id::text = PH.Comment
    WHERE PH.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Close, Reopen, Delete, Undelete, Lock, Unlock, Protect, Unprotect
      AND PH.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
ModeratorActionSummary AS (
    SELECT
        ModeratorId,
        ModeratorDisplayName,
        COUNT(DISTINCT PostId) AS TotalModeratedPosts,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 10 THEN PostId END) AS PostsClosedByMod,
        COUNT(DISTINCT CASE WHEN PostHistoryTypeId = 12 THEN PostId END) AS PostsDeletedByMod,
        AVG(EXTRACT(EPOCH FROM (EventDate - P_Created.CreationDate))) / (60*60*24) AS AvgDaysToModeration -- Average days from post creation to moderation
    FROM ModeratorInfluencedPosts M
    JOIN Posts P_Created ON M.PostId = P_Created.Id -- To get post creation date
    WHERE M.rn_latest_event = 1 -- Consider only the latest relevant event for aggregation
    GROUP BY ModeratorId, ModeratorDisplayName
)
SELECT
    AU.UserId,
    AU.DisplayName,
    AU.Reputation,
    AU.UserCreationDate,
    AU.LastAccessDate,
    AU.UserLocation,
    AU.AboutMeLength,
    AU.UserProfileViews,
    AU.UserGivenUpvotes,
    AU.UserGivenDownvotes,
    AU.TotalPosts,
    AU.QuestionsAsked,
    AU.AnswersGiven,
    AU.TotalPostScore,
    AU.AvgPostScore,
    AU.TotalComments,
    AU.TotalCommentScore,
    AU.TotalPostEdits,
    AU.UserPostsClosedCount,
    AU.TotalBadges,
    AU.GoldBadges,
    AU.SilverBadges,
    AU.BronzeBadges,
    AU.UpvotesCast,
    AU.DownvotesCast,
    AU.MostFrequentTag,
    AU.UserEngagementScore,
    AU.OverallRank,
    AU.PrevUserReputation,
    AU.AcceptedAnswersForOwnQuestions,
    AU.ContinentGroup,
    COALESCE(MAS.TotalModeratedPosts, 0) AS Moderator_TotalModeratedPosts,
    COALESCE(MAS.PostsClosedByMod, 0) AS Moderator_PostsClosedByMod,
    COALESCE(MAS.PostsDeletedByMod, 0) AS Moderator_PostsDeletedByMod,
    MAS.AvgDaysToModeration AS Moderator_AvgDaysToModeration,
    (
        SELECT
            COUNT(DISTINCT PL.RelatedPostId)
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT P_sub.Id FROM Posts P_sub WHERE P_sub.OwnerUserId = AU.UserId)
          AND PL.LinkTypeId = 1 -- Linked posts
          AND PL.CreationDate >= CURRENT_DATE - INTERVAL '6 months'
    ) AS RecentlyLinkedPostsFromOwnContent,
    SUM(CASE WHEN AU.QuestionsAsked > 0 AND AU.TotalPostEdits > 5 THEN 1 ELSE 0 END) OVER (PARTITION BY AU.ContinentGroup) AS HighEditQuestionUsersInContinent,
    NTILE(5) OVER (ORDER BY AU.UserEngagementScore DESC) AS EngagementQuintile
FROM ActiveUsers AU
LEFT JOIN ModeratorActionSummary MAS ON AU.UserId = MAS.ModeratorId
WHERE AU.UserEngagementScore > 500
  AND (AU.QuestionsAsked > 0 OR AU.AnswersGiven > 0)
  AND (AU.UserGivenUpvotes - AU.UserGivenDownvotes) > 100
  AND AU.TotalBadges >= 5
  AND AU.AboutMeLength IS NOT NULL
  AND AU.MostFrequentTag <> 'N/A'
UNION ALL
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    COALESCE(U.Location, 'Unknown') AS UserLocation,
    LENGTH(U.AboutMe) AS AboutMeLength,
    COALESCE(U.Views, 0) AS UserProfileViews,
    COALESCE(U.UpVotes, 0) AS UserGivenUpvotes,
    COALESCE(U.DownVotes, 0) AS UserGivenDownvotes,
    COALESCE(UAS.TotalPosts, 0) AS TotalPosts,
    COALESCE(UAS.QuestionsAsked, 0) AS QuestionsAsked,
    COALESCE(UAS.AnswersGiven, 0) AS AnswersGiven,
    COALESCE(UAS.TotalPostScore, 0) AS TotalPostScore,
    COALESCE(UAS.AvgPostScore, 0.0) AS AvgPostScore,
    COALESCE(CC.TotalComments, 0) AS TotalComments,
    COALESCE(CC.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(PES.TotalEditsMadeByUsersPosts, 0) AS TotalPostEdits,
    COALESCE(PES.UserPostsClosedCount, 0) AS UserPostsClosedCount,
    COALESCE(BS.TotalBadges, 0) AS TotalBadges,
    COALESCE(BS.GoldBadges, 0) AS GoldBadges,
    COALESCE(BS.SilverBadges, 0) AS SilverBadges,
    COALESCE(BS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UVI.UpvotesCast, 0) AS UpvotesCast,
    COALESCE(UVI.DownvotesCast, 0) AS DownvotesCast,
    COALESCE(UTT.TopTagName, 'N/A') AS MostFrequentTag,
    (U.Reputation * 0.5 + COALESCE(UAS.TotalPostScore, 0) * 0.3 + COALESCE(BS.GoldBadges, 0) * 10 + COALESCE(BS.SilverBadges, 0) * 5 + COALESCE(BS.BronzeBadges, 0) * 1) AS UserEngagementScore,
    RANK() OVER (ORDER BY (U.Reputation + COALESCE(UAS.TotalPostScore, 0)) DESC, U.LastAccessDate DESC) AS OverallRank,
    LAG(U.Reputation, 1, 0) OVER (ORDER BY U.CreationDate) AS PrevUserReputation,
    (SELECT COUNT(DISTINCT P_sub.Id) FROM Posts P_sub WHERE P_sub.OwnerUserId = U.Id AND P_sub.PostTypeId = 1 AND P_sub.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswersForOwnQuestions,
    CASE
        WHEN U.Location LIKE '%United States%' OR U.Location LIKE '%USA%' THEN 'North America'
        WHEN U.Location LIKE '%Canada%' THEN 'North America'
        WHEN U.Location LIKE '%UK%' OR U.Location LIKE '%United Kingdom%' THEN 'Europe'
        WHEN U.Location LIKE '%India%' THEN 'Asia'
        ELSE 'Other'
    END AS ContinentGroup,
    COALESCE(MAS.TotalModeratedPosts, 0) AS Moderator_TotalModeratedPosts,
    COALESCE(MAS.PostsClosedByMod, 0) AS Moderator_PostsClosedByMod,
    COALESCE(MAS.PostsDeletedByMod, 0) AS Moderator_PostsDeletedByMod,
    MAS.AvgDaysToModeration AS Moderator_AvgDaysToModeration,
    (
        SELECT
            COUNT(DISTINCT PL.RelatedPostId)
        FROM PostLinks PL
        WHERE PL.PostId IN (SELECT P_sub.Id FROM Posts P_sub WHERE P_sub.OwnerUserId = U.Id)
          AND PL.LinkTypeId = 3 -- Duplicate posts
          AND PL.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
    ) AS RecentlyDuplicatedPostsFromOwnContent,
    SUM(CASE WHEN UAS.AnswersGiven > 10 AND PES.UserPostsClosedCount > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY U.AccountId) AS TroubledAnswerersInAccount,
    NTILE(5) OVER (ORDER BY U.Reputation DESC) AS EngagementQuintile
FROM Users U
LEFT JOIN UserActivitySummary UAS ON U.Id = UAS.UserId
LEFT JOIN CommentContribution CC ON U.Id = CC.UserId
LEFT JOIN PostEditAndCloseStats PES ON U.Id = PES.UserId
LEFT JOIN BadgeSummary BS ON U.Id = BS.UserId
LEFT JOIN UserVoteInfluence UVI ON U.Id = UVI.UserId
LEFT JOIN UserTopTag UTT ON U.Id = UTT.UserId
LEFT JOIN ModeratorActionSummary MAS ON U.Id = MAS.ModeratorId
WHERE U.Reputation < 1000 AND U.Reputation > 100
  AND (U.CreationDate >= CURRENT_DATE - INTERVAL '3 years')
  AND U.DisplayName IS NOT NULL
  AND U.DisplayName LIKE 'A%'
  AND U.AboutMe IS NOT NULL
ORDER BY EngagementQuintile, UserEngagementScore DESC;
