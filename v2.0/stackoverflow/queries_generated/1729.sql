-- {"query": "1729.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2964} 

WITH UserActivitySummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserViews,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPosts,
        COALESCE(SUM(P.Score), 0) AS TotalPostScore,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViews,
        COALESCE(AVG(P.Score), 0.0) AS AvgPostScore,
        COALESCE(AVG(P.ViewCount), 0.0) AS AvgPostViewCount,
        -- Calculate a "profile completeness" score based on available profile information
        (CASE WHEN U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl != '' THEN 1 ELSE 0 END +
         CASE WHEN U.Location IS NOT NULL AND U.Location != '' THEN 1 ELSE 0 END +
         CASE WHEN U.AboutMe IS NOT NULL AND LENGTH(TRIM(U.AboutMe)) > 100 THEN 1 ELSE 0 END +
         CASE WHEN U.ProfileImageUrl IS NOT NULL THEN 1 ELSE 0 END) AS ProfileCompletenessScore,
        MAX(P.CreationDate) AS LastPostDateByUser
    FROM
        Users U
    LEFT JOIN
        Posts P ON U.Id = P.OwnerUserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views,
        U.WebsiteUrl, U.Location, U.AboutMe, U.ProfileImageUrl
),
PostCommentVoteStats AS (
    SELECT
        P.Id AS PostId,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS CommentCount,
        COALESCE(AVG(C.Score), 0.0) AS AvgCommentScore,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END), 0) AS TotalVotesReceived,
        -- Calculate upvote ratio, handling potential division by zero
        CASE
            WHEN COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END), 0) = 0 THEN 0.0
            ELSE COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) * 1.0 / COALESCE(SUM(CASE WHEN V.VoteTypeId IN (2, 3) THEN 1 ELSE 0 END), 0)
        END AS UpvoteRatio
    FROM
        Posts P
    LEFT JOIN
        Comments C ON P.Id = C.PostId
    LEFT JOIN
        Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2, 3) -- Only consider up/down votes
    GROUP BY
        P.Id
),
TagPerformance AS (
    SELECT
        U.Id AS UserId,
        T.TagName,
        COUNT(DISTINCT P.Id) AS PostsInTag,
        COALESCE(SUM(P.Score), 0) AS TagScore,
        COALESCE(AVG(P.Score), 0.0) AS AvgTagScore,
        COALESCE(SUM(P.ViewCount), 0) AS TagViews
    FROM
        Users U
    JOIN
        Posts P ON U.Id = P.OwnerUserId
    JOIN
        -- Parse the tags string into individual tags
        (SELECT Id, UNNEST(string_to_array(substring(Tags, 2, length(Tags)-2), '><')) AS TagName FROM Posts WHERE Tags IS NOT NULL AND LENGTH(Tags) > 2) AS PostTags
        ON P.Id = PostTags.Id
    JOIN
        Tags T ON PostTags.TagName = T.TagName
    GROUP BY
        U.Id, T.TagName
),
PostHistoryAnalysis AS (
    SELECT
        PH.PostId,
        MAX(CASE WHEN PH.PostHistoryTypeId = 10 AND CRT.Name IS NOT NULL THEN CRT.Name ELSE NULL END) AS ClosestCloseReason,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS CloseEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 11 THEN PH.Id END) AS ReopenEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4,5,6) THEN PH.Id END) AS EditEvents,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (12, 35) THEN PH.Id END) AS DeleteOrMigrateEvents
    FROM
        PostHistory PH
    LEFT JOIN
        CloseReasonTypes CRT ON (PH.PostHistoryTypeId = 10 AND PH.Comment = CRT.Id::text) -- Conditional join for close reasons
    WHERE
        PH.PostHistoryTypeId IN (10, 11, 4, 5, 6, 12, 35)
    GROUP BY
        PH.PostId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.QuestionCount,
    UAS.AnswerCount,
    UAS.TotalPosts,
    UAS.TotalPostScore,
    UAS.TotalPostViews,
    UAS.AvgPostScore,
    UAS.AvgPostViewCount,
    UAS.ProfileCompletenessScore,
    UAS.LastPostDateByUser,
    -- Window functions for ranking and analytical insights
    RANK() OVER (ORDER BY UAS.Reputation DESC, UAS.UpVotes DESC, UAS.DownVotes ASC) AS OverallReputationRank,
    NTILE(10) OVER (ORDER BY UAS.TotalPosts DESC, UAS.TotalPostScore DESC) AS PostVolumeDecile,
    LAG(UAS.Reputation, 1, 0) OVER (ORDER BY UAS.UserCreationDate, UAS.Id) AS ReputationOfPreviousUserCreated, -- Reputation of the user created just before this one
    COALESCE(AVG(CASE WHEN P_window.CreationDate >= UAS.LastAccessDate - INTERVAL '90 days' THEN P_window.Score ELSE NULL END)
        OVER (PARTITION BY UAS.UserId), 0.0) AS AvgRecentPostScore,
    -- Correlated Subquery: Find the latest comment date made by this user on any post they own
    (
        SELECT MAX(C.CreationDate)
        FROM Comments C
        WHERE C.UserId = UAS.UserId
        AND C.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = UAS.UserId)
    ) AS LastUserCommentOnOwnPostDate,
    -- Aggregate Comment and Vote Stats from CTEs, joined back via Posts
    COALESCE(SUM(PCVS.CommentCount), 0) AS TotalCommentsReceivedOnPosts,
    COALESCE(SUM(PCVS.UpvotesReceived), 0) AS TotalUpvotesReceivedOnPosts,
    COALESCE(SUM(PCVS.DownvotesReceived), 0) AS TotalDownvotesReceivedOnPosts,
    -- String expressions and NULL logic
    UPPER(LEFT(UAS.DisplayName, 3)) AS DisplayNamePrefix,
    COALESCE(LENGTH(TRIM(Users.AboutMe)), 0) AS AboutMeLength,
    REPLACE(COALESCE(Users.Location, 'N/A'), 'United States', 'USA') AS CleanedLocation,
    NULLIF(UAS.TotalPostScore, 0) AS TotalPostScoreOrNullIfZero, -- If total score is 0, make it NULL
    COALESCE(Users.WebsiteUrl, 'Not Provided') AS WebsiteURLStatus,
    -- Complex calculations / expressions
    (UAS.Reputation * 0.4 + UAS.UpVotes * 0.3 + UAS.TotalPostScore * 0.2 + UAS.ProfileCompletenessScore * 0.1) AS WeightedInfluenceScore,
    AGE(NOW(), UAS.UserCreationDate) AS AccountAge,
    -- Join with TagPerformance for most influential tags
    STRING_AGG(DISTINCT TP.TagName || ' (' || TP.PostsInTag || ' posts)', '; ' ORDER BY TP.PostsInTag DESC) AS TopTagsContribution,
    COALESCE(MAX(TP.AvgTagScore), 0.0) AS HighestAvgTagScoreForUserTags,
    -- Post history analysis
    STRING_AGG(DISTINCT PCH.ClosestCloseReason, '; ' ORDER BY PCH.ClosestCloseReason) AS DistinctCloseReasonsEncountered,
    COALESCE(SUM(PCH.CloseEvents), 0) AS TotalCloseEventsOnUsersPosts,
    COALESCE(SUM(PCH.EditEvents), 0) AS TotalEditEventsOnUsersPosts,
    COALESCE(SUM(PCH.DeleteOrMigrateEvents), 0) AS TotalDeleteOrMigrateEventsOnUsersPosts,
    -- Badges info
    COUNT(DISTINCT B.Id) AS TotalBadges,
    SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges,
    -- Link analysis
    COUNT(DISTINCT PL.RelatedPostId) AS TotalPostsLinkedFromUserPosts,
    COUNT(DISTINCT CASE WHEN PL.LinkTypeId = 3 THEN PL.RelatedPostId END) AS TotalDuplicateLinksByUsersPosts
FROM
    UserActivitySummary UAS
INNER JOIN
    Users ON UAS.UserId = Users.Id -- Rejoin Users table to access original AboutMe, Location, WebsiteUrl for string functions and NULL logic
LEFT JOIN
    Posts P_window ON UAS.UserId = P_window.OwnerUserId AND P_window.PostTypeId IN (1, 2) -- Rejoin Posts for window function on recent activity
LEFT JOIN
    PostCommentVoteStats PCVS ON P_window.Id = PCVS.PostId
LEFT JOIN
    TagPerformance TP ON UAS.UserId = TP.UserId
LEFT JOIN
    PostHistoryAnalysis PCH ON P_window.Id = PCH.PostId
LEFT JOIN
    Badges B ON UAS.UserId = B.UserId
LEFT JOIN
    PostLinks PL ON P_window.Id = PL.PostId
WHERE
    UAS.Reputation >= 5000 -- Filter for highly reputable users
    AND UAS.LastAccessDate >= NOW() - INTERVAL '1 year' -- Active in the last year
    AND (Users.AboutMe IS NOT NULL AND LENGTH(TRIM(Users.AboutMe)) > 200 OR UAS.TotalPosts > 50) -- Users with substantial profile info or significant post count
    AND P_window.PostTypeId IN (1, 2, 5) -- Only consider Questions, Answers, and TagWiki for comprehensive post analysis
    AND P_window.CreationDate >= UAS.UserCreationDate + INTERVAL '6 months' -- Exclude very early posts for some aggregated stats
GROUP BY
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.UserCreationDate, UAS.LastAccessDate, UAS.QuestionCount,
    UAS.AnswerCount, UAS.TotalPosts, UAS.TotalPostScore, UAS.TotalPostViews, UAS.AvgPostScore,
    UAS.AvgPostViewCount, UAS.ProfileCompletenessScore, UAS.LastPostDateByUser,
    Users.AboutMe, Users.Location, Users.WebsiteUrl, UAS.UpVotes, UAS.DownVotes
HAVING
    COUNT(DISTINCT B.Id) >= 10 -- Users with at least 10 badges
    AND (COALESCE(SUM(PCVS.UpvotesReceived), 0) > 100 OR COALESCE(SUM(P_window.FavoriteCount), 0) > 20) -- Significant upvotes or favorites
    AND AVG(UAS.AvgPostScore) > 5.0 -- Average post score by user is above 5
ORDER BY
    OverallReputationRank ASC, WeightedInfluenceScore DESC
LIMIT 2000;
