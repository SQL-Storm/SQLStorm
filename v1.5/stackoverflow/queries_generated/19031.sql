-- {"query": "19031.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3111} 
WITH PostVoteAggregates AS (
    -- Aggregate vote counts per post to avoid Cartesian product issues when joining with Users/Posts
    SELECT
        V.PostId,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived
    FROM
        Votes V
    GROUP BY
        V.PostId
),
UserActivitySummary AS (
    -- Summarize user-specific activity and post/comment contributions
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserTotalUpvotesGiven,
        U.DownVotes AS UserTotalDownvotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersCreated,
        COUNT(DISTINCT C.Id) AS TotalCommentsCreated,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScoreReceived,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViewsReceived,
        SUM(COALESCE(PVA.UpvotesReceived, 0)) AS TotalUpvotesReceivedOnPosts,
        SUM(COALESCE(PVA.DownvotesReceived, 0)) AS TotalDownvotesReceivedOnPosts,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsWithAcceptedAnswer,
        SUM(COALESCE(PVA.FavoritesReceived, 0)) AS TotalFavoritesReceivedOnPosts
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostVoteAggregates PVA ON P.Id = PVA.PostId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostTagEngagementBase AS (
    -- Process posts to extract tags and other engagement metrics
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount AS PostAnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.AcceptedAnswerId,
        STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><') AS ParsedTags,
        -- Count duplicate links for the post, if any
        COALESCE(COUNT(DISTINCT PL_Dup.RelatedPostId), 0) AS DuplicateLinkCount
    FROM
        Posts P
    LEFT JOIN PostLinks PL_Dup ON P.Id = PL_Dup.PostId AND PL_Dup.LinkTypeId = 3 -- Duplicate links
    WHERE
        P.PostTypeId IN (1, 2) -- Focus on Questions and Answers for tag context
        AND P.OwnerUserId IS NOT NULL -- Exclude posts without an owner (e.g., community wiki without initial owner)
        AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 -- Ensure tags exist
    GROUP BY
        P.Id, P.OwnerUserId, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount, P.CommentCount, P.FavoriteCount, P.AcceptedAnswerId, P.Tags
),
UserTagContributions AS (
    -- Aggregate user contributions per tag
    SELECT
        PTEB.OwnerUserId AS UserId,
        TagName_UNNEST AS TagName,
        SUM(PTEB.PostScore) AS UserScoreForTag,
        COUNT(PTEB.PostId) AS UserPostsForTag,
        AVG(PTEB.PostScore) AS UserAvgScoreForTag,
        MAX(PTEB.PostScore) AS UserMaxScoreForTag
    FROM
        PostTagEngagementBase PTEB
    CROSS JOIN UNNEST(PTEB.ParsedTags) AS TagName_UNNEST -- De-normalize tags for aggregation
    GROUP BY
        PTEB.OwnerUserId, TagName_UNNEST
),
UserTopTagPerformance AS (
    -- Identify each user's top-performing tag based on total score and post count
    SELECT
        UTC.UserId,
        UTC.TagName AS TopTagName,
        UTC.UserScoreForTag AS TopTagTotalScore,
        UTC.UserPostsForTag AS TopTagPostCount,
        UTC.UserAvgScoreForTag AS TopTagAvgScore,
        ROW_NUMBER() OVER (PARTITION BY UTC.UserId ORDER BY UTC.UserScoreForTag DESC, UTC.UserPostsForTag DESC, UTC.TagName ASC) AS rn
    FROM
        UserTagContributions UTC
),
UserContentHistoryAgg AS (
    -- Aggregate post history data for each user's own posts
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT PH.Id) AS TotalHistoryEntries,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) AND PH.UserId = P.OwnerUserId THEN PH.Id END) AS TotalEditsByOwner,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId IN (7, 8, 9) AND PH.UserId = P.OwnerUserId THEN PH.Id END) AS TotalRollbacksByOwner,
        COUNT(DISTINCT CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.Id END) AS TotalClosesOnOwnPosts,
        MAX(PH.CreationDate) AS LatestHistoryActionDate,
        -- Calculate average days from post creation to an edit by the owner
        AVG(EXTRACT(EPOCH FROM (PH.CreationDate - P.CreationDate))/3600/24) FILTER (WHERE PH.PostHistoryTypeId IN (4,5,6) AND PH.UserId = P.OwnerUserId) AS AvgDaysFromCreationToEditByOwner
    FROM
        Posts P
    LEFT JOIN PostHistory PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL
    GROUP BY
        P.OwnerUserId
),
UserBadgeCounts AS (
    -- Count badges for each user by class
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        COUNT(CASE WHEN B.Class = 1 THEN B.Id END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN B.Id END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN B.Id END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate,
        MIN(B.Date) AS FirstBadgeDate
    FROM
        Badges B
    GROUP BY
        B.UserId
)
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.UserCreationDate,
    UAS.LastAccessDate,
    UAS.UserProfileViews,
    UAS.TotalPostsCreated,
    UAS.TotalQuestionsCreated,
    UAS.TotalAnswersCreated,
    UAS.TotalCommentsCreated,
    UAS.TotalPostScoreReceived,
    UAS.TotalPostViewsReceived,
    UAS.TotalUpvotesReceivedOnPosts,
    UAS.TotalDownvotesReceivedOnPosts,
    UAS.TotalQuestionsWithAcceptedAnswer,
    UAS.TotalFavoritesReceivedOnPosts,

    UTTP.TopTagName,
    UTTP.TopTagTotalScore,
    UTTP.TopTagPostCount,
    UTTP.TopTagAvgScore,

    UCHA.TotalEditsByOwner,
    UCHA.TotalRollbacksByOwner,
    UCHA.TotalClosesOnOwnPosts,
    UCHA.LatestHistoryActionDate,
    COALESCE(UCHA.AvgDaysFromCreationToEditByOwner, 0) AS AvgDaysToFirstEditByOwner,

    UBC.TotalBadges,
    UBC.GoldBadges,
    UBC.SilverBadges,
    UBC.BronzeBadges,
    UBC.LastBadgeDate,
    UBC.FirstBadgeDate,

    -- Complex calculation: A hypothetical "Engagement Index"
    (
        (UAS.Reputation / 100.0)
        + (UAS.TotalPostScoreReceived * 0.5)
        + (UAS.TotalUpvotesReceivedOnPosts * 0.7)
        - (UAS.TotalDownvotesReceivedOnPosts * 0.3)
        + (UAS.TotalQuestionsWithAcceptedAnswer * 5.0)
        + (COALESCE(UTTP.TopTagTotalScore, 0) / 10.0)
        + (COBC.GoldBadges * 10.0)
        + (COBC.SilverBadges * 5.0)
        + (COBC.BronzeBadges * 1.0)
        - (COALESCE(UCHA.TotalClosesOnOwnPosts, 0) * 2.0) -- Penalize closed posts
    ) AS EngagementIndex,

    -- String Expression Example: Capped Display Name and Location Check
    UPPER(SUBSTRING(UAS.DisplayName, 1, 1)) || LOWER(SUBSTRING(UAS.DisplayName, 2, LEAST(LENGTH(UAS.DisplayName), 8))) AS CappedDisplayNamePrefix,
    CASE
        WHEN U.Location LIKE '%London%' OR U.Location LIKE '%New York%' OR U.Location LIKE '%San Francisco%' THEN 'Major Tech Hub'
        WHEN U.Location IS NULL OR TRIM(U.Location) = '' THEN 'Unknown Location'
        ELSE 'Other Geographic Region'
    END AS LocationCategory,

    -- NULL logic and Conditional expressions
    COALESCE(UAS.TotalAnswersCreated, 0) AS NonNullTotalAnswers,
    CASE
        WHEN UAS.TotalPostsCreated = 0 THEN 'No Posts'
        WHEN UAS.TotalQuestionsCreated > 0 AND UAS.TotalAnswersCreated = 0 THEN 'Questioner Only'
        WHEN UAS.TotalAnswersCreated > 0 AND UAS.TotalQuestionsCreated = 0 THEN 'Answerer Only'
        WHEN UAS.TotalQuestionsCreated > 0 AND UAS.TotalAnswersCreated > 0 THEN 'Balanced Contributor'
        ELSE 'Minimal/Other Activity'
    END AS UserRoleCategory,

    -- Correlated Subquery Example: Checks if the user has a tag-based badge related to their top tag
    EXISTS (
        SELECT 1
        FROM Badges B_corr
        WHERE B_corr.UserId = UAS.UserId
          AND B_corr.TagBased = TRUE
          AND LOWER(B_corr.Name) = LOWER(UTTP.TopTagName)
    ) AS HasTopTagBadge,

    -- Window Function Example: Rank users by EngagementIndex
    RANK() OVER (ORDER BY (
        (UAS.Reputation / 100.0)
        + (UAS.TotalPostScoreReceived * 0.5)
        + (UAS.TotalUpvotesReceivedOnPosts * 0.7)
        - (UAS.TotalDownvotesReceivedOnPosts * 0.3)
        + (UAS.TotalQuestionsWithAcceptedAnswer * 5.0)
        + (COALESCE(UTTP.TopTagTotalScore, 0) / 10.0)
        + (COBC.GoldBadges * 10.0)
        + (COBC.SilverBadges * 5.0)
        + (COBC.BronzeBadges * 1.0)
        - (COALESCE(UCHA.TotalClosesOnOwnPosts, 0) * 2.0)
    ) DESC, UAS.Reputation DESC, UAS.UserId ASC) AS OverallEngagementRank

FROM
    UserActivitySummary UAS
LEFT JOIN Users U ON UAS.UserId = U.Id -- Join back to Users for additional profile info like Location and AboutMe
LEFT JOIN UserTopTagPerformance UTTP ON UAS.UserId = UTTP.UserId AND UTTP.rn = 1
LEFT JOIN UserContentHistoryAgg UCHA ON UAS.UserId = UCHA.UserId
LEFT JOIN UserBadgeCounts UBC ON UAS.UserId = UBC.UserId
WHERE
    UAS.Reputation > 1000 -- Filter for more established users
    AND UAS.TotalPostsCreated > 0 -- Ensure they have contributed posts
    -- Complex predicate combining string functions, NULL checks, and numerical comparisons
    AND (
        (U.AboutMe IS NOT NULL AND LENGTH(TRIM(U.AboutMe)) > 100 AND POSITION('SQL' IN UPPER(U.AboutMe)) > 0)
        OR
        (U.WebsiteUrl IS NOT NULL AND U.WebsiteUrl LIKE '%github.com%')
        OR
        (U.Views > 500 AND UAS.TotalUpvotesReceivedOnPosts > 50)
    )
ORDER BY
    OverallEngagementRank ASC, UAS.UserId ASC
LIMIT 1000;