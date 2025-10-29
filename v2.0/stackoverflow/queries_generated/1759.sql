-- {"query": "1759.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3794} 

WITH UserSignificantEvents AS (
    -- Collect significant timestamped events for a subset of users.
    -- Uses UNION ALL to combine different event types and introduce a set operator.
    -- User ID sampling (e.g., U.Id % 50 = 0) is used to control data volume for benchmarking on large datasets.
    SELECT
        U.Id AS UserId,
        U.CreationDate AS EventDate,
        'AccountCreated' AS EventType,
        NULL::int AS RelatedPostId -- Explicit cast for consistency across UNION ALL
    FROM Users U
    WHERE U.Id % 50 = 0 AND U.Reputation > 500

    UNION ALL

    SELECT
        P.OwnerUserId AS UserId,
        P.CreationDate AS EventDate,
        'PostCreated' AS EventType,
        P.Id AS RelatedPostId
    FROM Posts P
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1,2) -- Questions and Answers
    AND P.OwnerUserId % 50 = 0 AND P.CreationDate BETWEEN '2015-01-01' AND '2020-01-01'

    UNION ALL

    SELECT
        B.UserId AS UserId,
        B.Date AS EventDate,
        'BadgeAwarded' AS EventType,
        NULL::int AS RelatedPostId
    FROM Badges B
    WHERE B.UserId % 50 = 0 AND B.Class = 1 -- Only Gold badges

    UNION ALL

    SELECT
        V.UserId AS UserId,
        V.CreationDate AS EventDate,
        'HighValueVote' AS EventType,
        V.PostId AS RelatedPostId
    FROM Votes V
    WHERE V.VoteTypeId IN (1,2) AND V.UserId IS NOT NULL -- AcceptedByOriginator, UpMod
    AND V.UserId % 50 = 0 AND V.CreationDate BETWEEN '2015-01-01' AND '2020-01-01'
),
UserActivitySummary AS (
    -- Summarize user activity including post counts, comment counts, and derived metrics from significant events.
    -- Uses LEFT JOINs for optional data and conditional SUM for vote type aggregation.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(CASE WHEN V.VoteTypeId IN (1, 2, 8) THEN 1 ELSE 0 END) AS TotalUpVotesGiven,
        SUM(CASE WHEN V.VoteTypeId IN (3, 4, 10, 12) THEN 1 ELSE 0 END) AS TotalDownVotesGiven,
        SUM(COALESCE(P.ViewCount, 0)) AS TotalPostViews, -- COALESCE for NULL ViewCount
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        MAX(P.CreationDate) AS LastPostDate,
        MIN(P.CreationDate) AS FirstPostDate,
        COUNT(USE.EventType) FILTER (WHERE USE.EventType = 'PostCreated') AS Event_PostsCreated,
        COUNT(USE.EventType) FILTER (WHERE USE.EventType = 'BadgeAwarded') AS Event_BadgesAwarded
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON U.Id = V.UserId
    LEFT JOIN UserSignificantEvents USE ON U.Id = USE.UserId
    WHERE U.Id % 50 = 0 -- Consistent sampling
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
    HAVING COUNT(DISTINCT P.Id) > 3 -- Filter for active users
),
PostContentAnalysis AS (
    -- Analyze post content, history, tag parsing, and use window functions.
    -- Includes a correlated subquery for edit history count.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        COALESCE(P.AnswerCount, 0) AS AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        LENGTH(P.Body) AS BodyLength,
        LENGTH(P.Title) AS TitleLength,
        P.LastEditDate,
        P.LastActivityDate,
        -- String expression to parse tags and calculate count, handling potential NULLs.
        COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'), 1), 0) AS TagCount,
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        -- Window function: Rank post by score within its PostTypeId.
        ROW_NUMBER() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.CreationDate ASC) AS RankInPostTypeByScore,
        -- Window function: Calculate time since the previous post by the same owner.
        LAG(P.CreationDate, 1) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostCreationDate,
        -- Correlated subquery to count specific post history entries (edits).
        (SELECT COUNT(DISTINCT PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4,5,6)) AS EditHistoryCount
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2)
    AND P.OwnerUserId IS NOT NULL
    AND P.OwnerUserId % 50 = 0 -- Consistent sampling
    AND P.CreationDate BETWEEN '2015-01-01' AND '2020-01-01'
),
RecentPostEngagement AS (
    -- Calculate recent engagement metrics for posts within a specific time window.
    -- Uses FILTER clause with aggregate functions for conditional counting/averaging.
    SELECT
        PCA.PostId,
        PCA.PostCreationDate,
        PCA.OwnerUserId,
        SUM(CASE WHEN V.VoteTypeId = 2 AND V.CreationDate BETWEEN PCA.PostCreationDate - INTERVAL '30 days' AND PCA.PostCreationDate + INTERVAL '90 days' THEN 1 ELSE 0 END) AS RecentUpVotes,
        SUM(CASE WHEN V.VoteTypeId = 3 AND V.CreationDate BETWEEN PCA.PostCreationDate - INTERVAL '30 days' AND PCA.PostCreationDate + INTERVAL '90 days' THEN 1 ELSE 0 END) AS RecentDownVotes,
        COUNT(DISTINCT C.Id) FILTER (WHERE C.CreationDate BETWEEN PCA.PostCreationDate - INTERVAL '30 days' AND PCA.PostCreationDate + INTERVAL '90 days') AS RecentComments,
        AVG(C.Score) FILTER (WHERE C.CreationDate BETWEEN PCA.PostCreationDate - INTERVAL '30 days' AND PCA.PostCreationDate + INTERVAL '90 days') AS AvgRecentCommentScore
    FROM PostContentAnalysis PCA
    LEFT JOIN Votes V ON PCA.PostId = V.PostId
    LEFT JOIN Comments C ON PCA.PostId = C.PostId
    GROUP BY PCA.PostId, PCA.PostCreationDate, PCA.OwnerUserId
),
HighImpactUsers AS (
    -- Identify high-impact users based on reputation and activity, and assign deciles.
    -- Uses NTILE window function.
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        UAS.Reputation,
        UAS.TotalPosts,
        UAS.TotalComments,
        (UAS.Reputation * 0.5 + UAS.TotalPosts * 0.2 + UAS.TotalComments * 0.3 + UAS.Event_BadgesAwarded * 0.1) AS ContributionScore,
        NTILE(10) OVER (ORDER BY UAS.Reputation DESC, UAS.TotalPosts DESC) AS ReputationDecile
    FROM UserActivitySummary UAS
    WHERE UAS.Reputation > 1000 AND UAS.TotalPosts > 5
),
BadgesAndPostLinks AS (
    -- Aggregate badge information, post link details, and associated tags.
    -- Includes complex string aggregation, COALESCE for NULL handling, and a correlated subquery for linked post tags.
    SELECT
        P.Id AS PostId,
        COUNT(DISTINCT B.Id) AS BadgesAwardedOnPostDate,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesOnPostDate,
        -- STRING_AGG for concatenation of distinct tags, handling NULLs with COALESCE.
        COALESCE(STRING_AGG(DISTINCT T.TagName, ' | ') FILTER (WHERE T.TagName IS NOT NULL AND T.TagName != ''), 'N/A') AS AssociatedTags,
        COUNT(DISTINCT PL.RelatedPostId) AS LinkedPostsCount,
        MAX(PL.CreationDate) AS LastLinkDate,
        -- Correlated subquery to calculate the average tag count of related posts.
        (
            SELECT AVG(COALESCE(ARRAY_LENGTH(string_to_array(SUBSTRING(P_Linked.Tags, 2, LENGTH(P_Linked.Tags)-2), '><'), 1), 0))
            FROM PostLinks PL_Inner
            JOIN Posts P_Linked ON PL_Inner.RelatedPostId = P_Linked.Id
            WHERE PL_Inner.PostId = P.Id
        ) AS AvgLinkedPostTagCount
    FROM Posts P
    LEFT JOIN Users U ON P.OwnerUserId = U.Id
    LEFT JOIN Badges B ON U.Id = B.UserId AND B.Date <= P.CreationDate
    LEFT JOIN PostLinks PL ON P.Id = PL.PostId OR P.Id = PL.RelatedPostId
    LEFT JOIN Tags T ON P.Tags LIKE '%' || T.TagName || '%' -- String matching for tags. Potentially costly.
    WHERE P.PostTypeId IN (1,2)
    GROUP BY P.Id
)
-- Final SELECT statement combining all CTEs with various functions and expressions.
SELECT
    HIU.UserId,
    HIU.DisplayName,
    HIU.Reputation,
    HIU.ContributionScore,
    HIU.ReputationDecile,
    PCA.PostId,
    PT.Name AS PostTypeName,
    PCA.PostCreationDate,
    PCA.PostScore,
    PCA.ViewCount,
    PCA.AnswerCount,
    PCA.PostCommentCount,
    PCA.BodyLength,
    PCA.TitleLength,
    PCA.LastEditDate,
    PCA.LastActivityDate,
    PCA.TagCount,
    PCA.PostStatus,
    PCA.RankInPostTypeByScore,
    -- Complicated calculation: time between user's posts in hours, handling potential NULLs.
    COALESCE(EXTRACT(EPOCH FROM (PCA.PostCreationDate - PCA.PrevPostCreationDate)) / 3600, 0.0) AS HoursSincePrevPost,
    COALESCE(RPE.RecentUpVotes, 0) AS PostRecentUpVotes,
    COALESCE(RPE.RecentDownVotes, 0) AS PostRecentDownVotes,
    COALESCE(RPE.RecentComments, 0) AS PostRecentComments,
    COALESCE(RPE.AvgRecentCommentScore, 0.0) AS AvgPostRecentCommentScore,
    BAL.BadgesAwardedOnPostDate,
    BAL.GoldBadgesOnPostDate,
    BAL.AssociatedTags,
    BAL.LinkedPostsCount,
    COALESCE(BAL.AvgLinkedPostTagCount, 0.0) AS AvgLinkedPostTagCount,
    BAL.LastLinkDate,
    -- A very complicated expression combining multiple metrics with weighting.
    (
        (PCA.PostScore * 0.4)
        + (COALESCE(PCA.ViewCount, 0) * 0.1 / 100.0) -- Scale view count to prevent dominance.
        + (COALESCE(PCA.AnswerCount, 0) * 0.2)
        + (COALESCE(RPE.RecentUpVotes, 0) * 0.3)
        + (COALESCE(BAL.GoldBadgesOnPostDate, 0) * 0.5)
        + (COALESCE(PCA.EditHistoryCount, 0) * 0.05)
    ) AS PostEngagementMetric,
    -- NULL logic: Prevent division by zero for ratio calculation.
    NULLIF(UAS.TotalUpVotesGiven, 0)::numeric / NULLIF(UAS.TotalDownVotesGiven, 0) AS UpVoteToDownVoteRatio,
    -- Correlated subquery for average comment length by the specific user on this post.
    (
        SELECT AVG(LENGTH(C.Text))
        FROM Comments C
        WHERE C.PostId = PCA.PostId AND C.UserId = HIU.UserId
        AND C.CreationDate BETWEEN PCA.PostCreationDate - INTERVAL '1 day' AND PCA.PostCreationDate + INTERVAL '30 days'
        AND C.Text IS NOT NULL
    ) AS AvgUserCommentLengthAroundPost,
    -- Complicated CASE statement for categorizing posts based on multiple criteria.
    CASE
        WHEN PCA.BodyLength > 1000 AND PCA.TagCount >= 5 AND PCA.PostStatus = 'Open' AND PCA.PostScore > 10 THEN 'Detailed & Highly Active'
        WHEN PCA.PostScore > 50 AND COALESCE(PCA.ViewCount, 0) > 10000 AND PCA.FavoriteCount > 10 THEN 'High Visibility & Favored'
        WHEN PCA.PostCreationDate < HIU.UserCreationDate + INTERVAL '90 days' AND PCA.PostScore > 5 THEN 'Early Contribution & Impactful'
        WHEN PCA.LastEditDate IS NOT NULL AND PCA.LastEditDate > NOW() - INTERVAL '6 months' THEN 'Recently Maintained'
        ELSE 'General'
    END AS PostCategoryDescription,
    -- Window function: Moving average of post scores for the user.
    AVG(PCA.PostScore) OVER (PARTITION BY HIU.UserId ORDER BY PCA.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS UserMovingAvgPostScore,
    -- Window function: Difference in Reputation from the previous user within the same reputation decile.
    HIU.Reputation - LAG(HIU.Reputation, 1, HIU.Reputation) OVER (PARTITION BY HIU.ReputationDecile ORDER BY HIU.Reputation) AS ReputationDiffInDecile,
    -- String expressions: Concatenate current date, user display name, and zero-padded post ID.
    TO_CHAR(NOW(), 'YYYY-MM-DD') || ' - ' || UPPER(LEFT(COALESCE(HIU.DisplayName, 'UNKNOWN'), 3)) || ' - ' || LPAD(PCA.PostId::text, 10, '0') AS ReportIdentifier
FROM HighImpactUsers HIU
JOIN UserActivitySummary UAS ON HIU.UserId = UAS.UserId
JOIN PostContentAnalysis PCA ON HIU.UserId = PCA.OwnerUserId
JOIN PostTypes PT ON PCA.PostTypeId = PT.Id
LEFT JOIN RecentPostEngagement RPE ON PCA.PostId = RPE.PostId AND PCA.OwnerUserId = RPE.OwnerUserId
LEFT JOIN BadgesAndPostLinks BAL ON PCA.PostId = BAL.PostId
WHERE
    PCA.PostCreationDate BETWEEN HIU.UserCreationDate AND HIU.UserCreationDate + INTERVAL '3 years'
    AND PCA.PostScore > -5
    AND (
        PCA.Title ILIKE '%SQL%' -- Case-insensitive string search.
        OR PCA.Title ILIKE '%database%'
        OR BAL.AssociatedTags ILIKE '%sql%'
        OR BAL.AssociatedTags ILIKE '%database%'
        OR PCA.BodyLength > 2000 -- Posts with very long bodies
    )
    AND PCA.BodyLength IS NOT NULL AND PCA.BodyLength > 50
ORDER BY HIU.Reputation DESC, HIU.UserId, PCA.PostCreationDate DESC, PCA.PostId
LIMIT 2000;
