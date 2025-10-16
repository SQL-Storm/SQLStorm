-- {"query": "19012.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3514} 

WITH UserActivity AS (
    -- Summarize posts, comments, and specific post history events for each user
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
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId AND P.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    LEFT JOIN Comments C ON U.Id = C.UserId AND C.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    LEFT JOIN PostHistory PH_Edit ON U.Id = PH_Edit.UserId AND PH_Edit.PostHistoryTypeId IN (4, 5, 6) AND PH_Edit.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    LEFT JOIN PostHistory PH_Close ON U.Id = PH_Close.UserId AND PH_Close.PostHistoryTypeId = 10 AND PH_Close.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '5 year')
    GROUP BY U.Id
),
PostTagParser AS (
    -- Parse tags from posts for analytical use (PostgreSQL string functions assumed as per schema description)
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate,
        P.Score,
        TRIM(REPLACE(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')), ' ', '')) AS TagName
    FROM Posts P
    WHERE P.PostTypeId = 1 -- Only questions have tags relevant for "hot tags" analysis
      AND P.Tags IS NOT NULL
      AND LENGTH(P.Tags) > 2
),
HotTags AS (
    -- Identify "hot" tags based on recent activity and score thresholds
    SELECT
        PTP.TagName,
        COUNT(DISTINCT PTP.PostId) AS TaggedPostCount,
        AVG(PTP.Score * 1.0) AS AverageTagPostScore
    FROM PostTagParser PTP
    WHERE PTP.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 year')
    GROUP BY PTP.TagName
    HAVING COUNT(DISTINCT PTP.PostId) > 1000 -- Tagged in more than 1000 posts in the last 3 years
       AND AVG(PTP.Score * 1.0) > 10 -- Average score greater than 10
),
UserTagEngagement AS (
    -- Count distinct hot tags a user has engaged with, and related post stats
    SELECT
        PTP.OwnerUserId AS UserId,
        COUNT(DISTINCT HT.TagName) AS DistinctHotTagContributions,
        COUNT(DISTINCT PTP.PostId) AS TotalPostsInHotTags,
        SUM(PTP.Score) AS TotalScoreInHotTags
    FROM PostTagParser PTP
    INNER JOIN HotTags HT ON PTP.TagName = HT.TagName
    WHERE PTP.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '2 year')
    GROUP BY PTP.OwnerUserId
),
UserBadgeSummary AS (
    -- Summarize badge counts per user
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
    -- Summarize votes given by users, including accepted answers marked by them
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
    -- Analyze specific post history events and linked posts for user's owned posts
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
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId AND PH.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '4 year')
    LEFT JOIN PostLinks PL_Linked ON P.Id = PL_Linked.PostId AND PL_Linked.LinkTypeId = 1 AND PL_Linked.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '4 year')
    LEFT JOIN PostLinks PL_Duplicate ON P.Id = PL_Duplicate.PostId AND PL_Duplicate.LinkTypeId = 3 AND PL_Duplicate.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '4 year')
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY P.OwnerUserId
),
UserOverallRank AS (
    -- Rank users based on various criteria across the entire user base
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
        (U.LastAccessDate - U.CreationDate) AS AccountLifetime, -- Returns INTERVAL in PostgreSQL
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
                    U.WebsiteUrl,
                    POSITION('//' IN U.WebsiteUrl) + 2,
                    COALESCE(
                        NULLIF(POSITION('/' IN SUBSTRING(U.WebsiteUrl, POSITION('//' IN U.WebsiteUrl) + 2)), 0),
                        LENGTH(SUBSTRING(U.WebsiteUrl, POSITION('//' IN U.WebsiteUrl) + 2)) + 1
                    ) - 1
                ),
                'N/A'
            )
        ) AS DomainRoot,
        SUBSTRING(COALESCE(U.AboutMe, 'No detailed "About Me" provided.'), 1, 150) AS AboutMeSnippet
    FROM Users U
    LEFT JOIN UserActivity UA ON U.Id = UA.UserId
    LEFT JOIN UserBadgeSummary UB ON U.Id = UB.UserId
    LEFT JOIN UserTagEngagement HTE ON U.Id = HTE.UserId
    LEFT JOIN UserVoteOverview UVO ON U.Id = UVO.UserId
    LEFT JOIN PostHistoricalContext PHC ON U.Id = PHC.UserId
    LEFT JOIN CloseReasonTypes CR ON PHC.LatestCloseReasonId = CR.Id
    LEFT JOIN UserOverallRank UR ON U.Id = UR.UserId
    WHERE
        U.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '8 year')
        AND U.Reputation > 20000
        AND U.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '3 month')
        AND COALESCE(UB.GoldBadges, 0) >= 3
        AND COALESCE(HTE.DistinctHotTagContributions, 0) >= 5
        AND (COALESCE(UA.TotalPosts, 0) + COALESCE(UA.TotalCommentsMade, 0)) > 200
        AND U.Location IS NOT NULL AND U.Location LIKE '%State%' -- Example location filter
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
                    U.WebsiteUrl,
                    POSITION('//' IN U.WebsiteUrl) + 2,
                    COALESCE(
                        NULLIF(POSITION('/' IN U.WebsiteUrl, POSITION('//' IN U.WebsiteUrl) + 2), 0),
                        LENGTH(SUBSTRING(U.WebsiteUrl, POSITION('//' IN U.WebsiteUrl) + 2)) + 1
                    ) - 1
                ),
                'N/A'
            )
        ) AS DomainRoot,
        SUBSTRING(COALESCE(U.AboutMe, 'No detailed "About Me" provided.'), 1, 150) AS AboutMeSnippet
    FROM Users U
    LEFT JOIN UserActivity UA ON U.Id = UA.UserId
    LEFT JOIN UserBadgeSummary UB ON U.Id = UB.UserId
    LEFT JOIN UserTagEngagement HTE ON U.Id = HTE.UserId
    LEFT JOIN UserVoteOverview UVO ON U.Id = UVO.UserId
    LEFT JOIN PostHistoricalContext PHC ON U.Id = PHC.UserId
    LEFT JOIN CloseReasonTypes CR ON PHC.LatestCloseReasonId = CR.Id
    LEFT JOIN UserOverallRank UR ON U.Id = UR.UserId
    WHERE
        U.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 year')
        AND U.Reputation > 5000
        AND U.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1 month')
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
