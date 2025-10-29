-- {"query": "1879.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2732} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS QuestionsCount,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS AnswersCount,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(CASE WHEN V.VoteTypeId = 8 THEN COALESCE(V.BountyAmount, 0) ELSE 0 END) AS TotalBountyPosted,
        MAX(COALESCE(P.LastActivityDate, P.CreationDate, U.LastAccessDate)) AS LastActivityByAnything,
        MIN(U.CreationDate) AS FirstUserActivityDate
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.WebsiteUrl, U.Location, U.AboutMe
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.Title,
        P.CreationDate AS PostCreationDate,
        P.Score AS CurrentScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.ClosedDate,
        P.CommunityOwnedDate,
        -- String expression: Extracting tags without leading/trailing delimiters
        SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2) AS RawTagsString,
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 1
            ELSE 0
        END AS HasAcceptedAnswer,
        -- Complicated calculation: Post age in days
        EXTRACT(EPOCH FROM (NOW() - P.CreationDate)) / (60 * 60 * 24) AS PostAgeInDays,
        -- Complex CASE expression combining multiple conditions
        CASE
            WHEN P.Score > 100 AND P.ViewCount > 10000 AND P.AnswerCount > 5 THEN 'Viral_Popular_Answered'
            WHEN P.Score > 50 AND P.ViewCount > 5000 THEN 'Highly_Viewed_Scored'
            WHEN P.CommentCount > 20 AND P.Score > 10 THEN 'Heavily_Commented_And_Liked'
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed_Post'
            ELSE 'Standard_Or_Other'
        END AS PostPopularityCategory,
        -- String expression: Check if title contains a common programming term
        (P.Title ILIKE '%SQL%' OR P.Title ILIKE '%C#%' OR P.Title ILIKE '%Python%') AS IsTechSpecificTitle
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Focus on Questions (1) and Answers (2)
),
PostHistoryAggregations AS (
    SELECT
        PH.PostId,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditRevisionsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedEventsCount,
        SUM(CASE WHEN PH.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeletedEventsCount,
        MAX(PH.CreationDate) AS LastHistoryEventDate
    FROM PostHistory PH
    GROUP BY PH.PostId
),
UserBadgeSummary AS (
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldenBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeDate
    FROM Badges B
    GROUP BY B.UserId
),
TagUsageRankedPerPost AS (
    SELECT
        T.PostId,
        T.OwnerUserId,
        TRIM(UNNEST(string_to_array(T.RawTagsString, '><'))) AS TagName,
        -- Window function: Rank tags by count per post (mostly 1 unless data issue) but demonstrates PARTITION BY
        ROW_NUMBER() OVER (PARTITION BY T.PostId ORDER BY COUNT(TRIM(UNNEST(string_to_array(T.RawTagsString, '><')))) DESC, TRIM(UNNEST(string_to_array(T.RawTagsString, '><')))) AS TagRankInPost
    FROM PostDetailsExtended T
    WHERE T.RawTagsString IS NOT NULL AND LENGTH(T.RawTagsString) > 0
    GROUP BY T.PostId, T.OwnerUserId, TRIM(UNNEST(string_to_array(T.RawTagsString, '><')))
),
GlobalTagPopularity AS (
    SELECT
        TagName,
        COUNT(DISTINCT PostId) AS TaggedPostCount,
        AVG(PDE.CurrentScore) AS AvgPostScoreForTag
    FROM TagUsageRankedPerPost T
    JOIN PostDetailsExtended PDE ON T.PostId = PDE.PostId
    GROUP BY TagName
    HAVING COUNT(DISTINCT PostId) > 50 -- Only consider reasonably popular tags
),
QualifiedContributors AS (
    -- Set operator: UNION ALL to combine two distinct groups of qualified users
    -- Group 1: Users with high total upvotes given and high reputation
    SELECT UES.UserId, 'HighUpvoteGiver' AS QualificationType
    FROM UserEngagementSummary UES
    WHERE UES.TotalUpVotesGiven > 500 AND UES.Reputation > 5000
    UNION ALL
    -- Group 2: Users who have provided many answers that were accepted
    SELECT P.OwnerUserId AS UserId, 'ProlificAcceptedAnswerer' AS QualificationType
    FROM Posts P
    WHERE P.PostTypeId = 2 AND P.AcceptedAnswerId IS NOT NULL
    GROUP BY P.OwnerUserId
    HAVING COUNT(P.Id) > 10
),
-- This CTE will be used in a correlated subquery later to check for duplicate links
PostsWithDuplicateLinks AS (
    SELECT DISTINCT RelatedPostId AS DuplicatedPostId
    FROM PostLinks
    WHERE LinkTypeId = 3
)
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.TotalPostsCreated,
    UES.QuestionsCount,
    UES.AnswersCount,
    UES.TotalCommentsMade,
    UES.TotalUpVotesGiven,
    UES.TotalDownVotesGiven,
    -- Window function: Rank users globally by reputation and recent activity
    DENSE_RANK() OVER (ORDER BY UES.Reputation DESC, UES.LastAccessDate DESC) AS OverallUserReputationRank,
    -- Complicated calculation/expression with NULL logic
    COALESCE(CAST(UES.TotalUpVotesGiven AS DECIMAL) / NULLIF(UES.TotalPostsCreated + UES.TotalCommentsMade + UES.TotalDownVotesGiven, 0), 0) AS NetEngagementRatio,
    -- String expression and NULL logic
    COALESCE(UES.Location, 'Unknown Location') AS UserLocation,
    -- Join to PostDetailsExtended to get details of the user's latest post
    PDE_Latest.Title AS LatestPostTitle,
    PDE_Latest.PostCreationDate AS LatestPostDate,
    PDE_Latest.CurrentScore AS LatestPostScore,
    PDE_Latest.ViewCount AS LatestPostViewCount,
    PDE_Latest.PostAgeInDays AS LatestPostAgeInDays,
    PDE_Latest.PostPopularityCategory AS LatestPostPopularityCategory,
    PDE_Latest.IsTechSpecificTitle,
    -- Join to PostHistoryAggregations for history of the latest post
    PHA.EditRevisionsCount AS LatestPostEditCount,
    PHA.ClosedEventsCount AS LatestPostClosedCount,
    PHA.DeletedEventsCount AS LatestPostDeletedCount,
    -- Join to UserBadgeSummary
    UBS.GoldenBadges,
    UBS.SilverBadges,
    UBS.BronzeBadges,
    -- Correlated subquery example: Check if any post owned by this user has ever been a duplicate target
    EXISTS (
        SELECT 1
        FROM Posts P_corr
        INNER JOIN PostsWithDuplicateLinks PDL_corr ON P_corr.Id = PDL_corr.DuplicatedPostId
        WHERE P_corr.OwnerUserId = UES.UserId
          AND P_corr.CreationDate >= UES.UserCreationDate
    ) AS HasPostsTargetedAsDuplicates,
    -- String expression: Extract the first 50 chars of AboutMe or a default
    SUBSTRING(COALESCE(UES.AboutMe, 'No "About Me" description.'), 1, 50) AS AboutMeExcerpt,
    -- Window function: NTILE for reputation distribution
    NTILE(10) OVER (ORDER BY UES.Reputation DESC) AS ReputationDecile,
    -- Another correlated subquery in SELECT for last edited post
    (
        SELECT P_last_edit.Title
        FROM Posts P_last_edit
        WHERE P_last_edit.OwnerUserId = UES.UserId
          AND P_last_edit.LastEditDate IS NOT NULL
        ORDER BY P_last_edit.LastEditDate DESC
        LIMIT 1
    ) AS LastEditedPostTitleByUser,
    -- Join to get the primary tag of the latest post and its global popularity
    COALESCE(TRP.TagName, 'Untagged/No-Tag-Data') AS PrimaryTagOfLatestPost,
    COALESCE(GTP.TaggedPostCount, 0) AS PrimaryTagGlobalPopularity,
    -- Complicated predicate in WHERE clause using various conditions and string matching
    (UES.TotalPostsCreated > 5 AND UES.Reputation > 500 AND UES.TotalUpVotesGiven > 20)
    AND (
        UES.Location ILIKE '%America%' OR UES.WebsiteUrl ILIKE '%linkedin.com%' OR UES.AboutMe ILIKE '%developer%'
    )
    AND EXISTS (SELECT 1 FROM QualifiedContributors QC WHERE QC.UserId = UES.UserId AND QC.QualificationType = 'HighUpvoteGiver')
    AND UES.UserCreationDate >= NOW() - INTERVAL '5 year' -- Filter for users created in the last 5 years
    AND NOT EXISTS (
        SELECT 1 FROM Posts P_del
        JOIN PostHistory PH_del ON P_del.Id = PH_del.PostId
        WHERE P_del.OwnerUserId = UES.UserId
          AND PH_del.PostHistoryTypeId = 12 -- Post Deleted
          AND PH_del.CreationDate > P_del.CreationDate
    ) -- Exclude users with any deleted posts history
ORDER BY
    OverallUserReputationRank ASC,
    NetEngagementRatio DESC NULLS LAST,
    UES.LastAccessDate DESC
LIMIT 5000;
