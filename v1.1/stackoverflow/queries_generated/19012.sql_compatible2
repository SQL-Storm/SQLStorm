WITH UserActivity AS (
    SELECT
        U.Id AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT PH_Edit.Id) AS TotalEditsContributed,
        COUNT(DISTINCT PH_Close.PostId) AS TotalPostsClosedByOwner,
        MIN(COALESCE(P.CreationDate, C.CreationDate, PH_Edit.CreationDate)) AS FirstActivityDate,
        MAX(COALESCE(P.CreationDate, C.CreationDate, PH_Edit.CreationDate)) AS LastActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
    LEFT JOIN Comments C ON U.Id = C.UserId AND C.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
    LEFT JOIN PostHistory PH_Edit ON U.Id = PH_Edit.UserId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) AND PH_Edit.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
    LEFT JOIN PostHistory PH_Close ON U.Id = PH_Close.UserId AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '5' YEAR)
    GROUP BY U.Id
),
PostTagParser AS (
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        TRIM(REPLACE(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR (LENGTH(P.Tags) - 2)), '><')), ' ', '')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1
      AND P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
),
HotTags AS (
    SELECT
        PTP.TagName,
        COUNT(DISTINCT PTP.PostId) AS TaggedPostCount,
        AVG(PTP.Score * 1.0) AS AverageTagPostScore
    FROM PostTagParser PTP
    WHERE PTP.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3' YEAR)
    GROUP BY PTP.TagName
    HAVING COUNT(DISTINCT PTP.PostId) > 1000
       AND AVG(PTP.Score * 1.0) > 10
),
UserTagEngagement AS (
    SELECT
        PTP.OwnerUserId AS UserId,
        COUNT(DISTINCT HT.TagName) AS DistinctHotTagContributions,
        COUNT(DISTINCT PTP.PostId) AS TotalPostsInHotTags,
        SUM(PTP.Score) AS TotalScoreInHotTags
    FROM PostTagParser PTP
    INNER JOIN HotTags HT ON PTP.TagName = HT.TagName
    WHERE PTP.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '2' YEAR)
    GROUP BY PTP.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges B
    GROUP BY B.UserId
),
UserVoteOverview AS (
    SELECT
        V.UserId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedAnswersAwarded
    FROM Votes V
    WHERE V.UserId IS NOT NULL
    GROUP BY V.UserId
),
PostHistoricalContext AS (
    SELECT
        P.OwnerUserId AS UserId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 THEN CAST(PH.Comment AS SMALLINT) ELSE NULL END) AS LatestCloseReasonId,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 19 THEN 1 ELSE NULL END) AS ProtectionEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId = 16 THEN 1 ELSE NULL END) AS CommunityOwnedEvents,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE NULL END) AS EditsOnOwnedPosts,
        COUNT(DISTINCT PL_Linked.RelatedPostId) AS TotalLinkedPostsCount,
        COUNT(DISTINCT PL_Duplicate.RelatedPostId) AS TotalDuplicatePostsCount
    FROM Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '4' YEAR)
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 AND PL_Linked.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '4' YEAR)
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 AND PL_Duplicate.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '4' YEAR)
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserOverallRank AS (
    SELECT
        U.Id AS UserId,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views,
        U.UpVotes,
        U.DownVotes,
        U.AccountId,
        RANK() OVER (ORDER BY U.Reputation DESC, U.LastAccessDate DESC) AS GlobalReputationRank,
        NTILE(10) OVER (ORDER BY U.UpVotes DESC, U.DownVotes ASC) AS UpvoteEfficiencyDecile
    FROM Users U
    WHERE U.Reputation > 0
),
VeteranInfluencers AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COALESCE(UA.TotalPosts, 0) AS TotalContributions,
        COALESCE(UA.TotalQuestions, 0) AS QuestionsAsked,
        COALESCE(UA.TotalAnswers, 0) AS AnswersProvided,
        COALESCE(UA.TotalCommentsMade, 0) AS CommentsMade,
        COALESCE(UB.GoldBadges, 0) AS GoldBadgesCount,
        COALESCE(HTE.DistinctHotTagContributions, 0) AS EngagedHotTagsCount,
        COALESCE(UVO.UpvotesGiven, 0) AS UserUpvotesGiven,
        COALESCE(UVO.DownvotesGiven, 0) AS UserDownvotesGiven,
        (U.UpVotes * 1.0 / NULLIF(U.Views, 0)) AS KarmaPerViewRatio,
        (COALESCE(UA.TotalEditsContributed, 0) * 1.0 / NULLIF(UA.TotalPosts, 0)) AS EditToContributionRatio,
        (U.LastAccessDate - U.CreationDate) AS AccountLifetime,
        CR.Name AS LatestClosureReason,
        COALESCE(PHC.ReopenEvents, 0) AS PostReopenEvents,
        COALESCE(PHC.ProtectionEvents, 0) AS PostProtectionEvents,
        COALESCE(PHC.TotalLinkedPostsCount, 0) AS PostsWithLinksCount,
        UR.GlobalReputationRank,
        'Veteran Influencer' AS UserCategory,
        NULLIF(U.Location, '') AS Location,
        UPPER(
            COALESCE(
                SUBSTRING(
                    U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2) FOR (
                        COALESCE(
                            NULLIF(POSITION('/' IN SUBSTRING(U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2))), 0),
                            LENGTH(SUBSTRING(U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2))) + 1
                        ) - 1
                    )
                ),
                'N/A'
            )
        ) AS DomainRoot,
        SUBSTRING(COALESCE(U.AboutMe, 'No detailed "About Me" provided.' ) FROM 1 FOR 150) AS AboutMeSnippet
    FROM Users U
    LEFT JOIN UserActivity UA ON U.Id = UA.UserId
    LEFT JOIN UserBadgeSummary UB ON U.Id = UB.UserId
    LEFT JOIN UserTagEngagement HTE ON U.Id = HTE.UserId
    LEFT JOIN UserVoteOverview UVO ON U.Id = UVO.UserId
    LEFT JOIN PostHistoricalContext PHC ON U.Id = PHC.UserId
    LEFT JOIN CloseReasonTypes CR ON PHC.LatestCloseReasonId = CR.Id
    LEFT JOIN UserOverallRank UR ON U.Id = UR.UserId
    WHERE
        U.CreationDate < (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '8' YEAR)
        AND U.Reputation > 20000
        AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3' MONTH)
        AND COALESCE(UB.GoldBadges, 0) >= 3
        AND COALESCE(HTE.DistinctHotTagContributions, 0) >= 5
        AND (COALESCE(UA.TotalPosts, 0) + COALESCE(UA.TotalCommentsMade, 0)) > 200
        AND U.Location IS NOT NULL AND U.Location LIKE '%State%'
        AND U.Views > 1000
        AND U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 250
),
NicheRisingStars AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        COALESCE(UA.TotalPosts, 0) AS TotalContributions,
        COALESCE(UA.TotalQuestions, 0) AS QuestionsAsked,
        COALESCE(UA.TotalAnswers, 0) AS AnswersProvided,
        COALESCE(UA.TotalCommentsMade, 0) AS CommentsMade,
        COALESCE(UB.GoldBadges, 0) AS GoldBadgesCount,
        COALESCE(HTE.DistinctHotTagContributions, 0) AS EngagedHotTagsCount,
        COALESCE(UVO.UpvotesGiven, 0) AS UserUpvotesGiven,
        COALESCE(UVO.DownvotesGiven, 0) AS UserDownvotesGiven,
        (U.UpVotes * 1.0 / NULLIF(U.Views, 0)) AS KarmaPerViewRatio,
        (COALESCE(UA.TotalEditsContributed, 0) * 1.0 / NULLIF(UA.TotalPosts, 0)) AS EditToContributionRatio,
        (U.LastAccessDate - U.CreationDate) AS AccountLifetime,
        CR.Name AS LatestClosureReason,
        COALESCE(PHC.ReopenEvents, 0) AS PostReopenEvents,
        COALESCE(PHC.ProtectionEvents, 0) AS PostProtectionEvents,
        COALESCE(PHC.TotalLinkedPostsCount, 0) AS PostsWithLinksCount,
        UR.GlobalReputationRank,
        'Niche Rising Star' AS UserCategory,
        NULLIF(U.Location, '') AS Location,
        UPPER(
            COALESCE(
                SUBSTRING(
                    U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2) FOR (
                        COALESCE(
                            NULLIF(POSITION('/' IN SUBSTRING(U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2))), 0),
                            LENGTH(SUBSTRING(U.WebsiteUrl FROM (POSITION('//' IN U.WebsiteUrl) + 2))) + 1
                        ) - 1
                    )
                ),
                'N/A'
            )
        ) AS DomainRoot,
        SUBSTRING(COALESCE(U.AboutMe, 'No detailed "About Me" provided.' ) FROM 1 FOR 150) AS AboutMeSnippet
    FROM Users U
    LEFT JOIN UserActivity UA ON U.Id = UA.UserId
    LEFT JOIN UserBadgeSummary UB ON U.Id = UB.UserId
    LEFT JOIN UserTagEngagement HTE ON U.Id = HTE.UserId
    LEFT JOIN UserVoteOverview UVO ON U.Id = UVO.UserId
    LEFT JOIN PostHistoricalContext PHC ON U.Id = PHC.UserId
    LEFT JOIN CloseReasonTypes CR ON PHC.LatestCloseReasonId = CR.Id
    LEFT JOIN UserOverallRank UR ON U.Id = UR.UserId
    WHERE
        U.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3' YEAR)
        AND U.Reputation > 5000
        AND U.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1' MONTH)
        AND COALESCE(HTE.DistinctHotTagContributions, 0) BETWEEN 1 AND 4
        AND COALESCE(HTE.TotalPostsInHotTags, 0) * 1.0 / NULLIF(COALESCE(UA.TotalPosts, 0), 0) > 0.6
        AND COALESCE(UA.TotalAnswers, 0) > COALESCE(UA.TotalQuestions, 0) * 2
        AND COALESCE(UVO.AcceptedAnswersAwarded, 0) > 5
        AND U.ProfileImageUrl IS NOT NULL
        AND UR.UpvoteEfficiencyDecile <= 3
)
SELECT *
FROM VeteranInfluencers
WHERE KarmaPerViewRatio IS NOT NULL AND KarmaPerViewRatio > 0.05
UNION ALL
SELECT *
FROM NicheRisingStars
WHERE KarmaPerViewRatio IS NOT NULL AND KarmaPerViewRatio > 0.01
ORDER BY UserCategory DESC, Reputation DESC, KarmaPerViewRatio DESC
LIMIT 200;