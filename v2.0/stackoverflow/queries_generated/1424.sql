-- {"query": "1424.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3561} 

WITH UserEngagement AS (
    -- CTE 1: Summarize user activity and derive aggregated metrics.
    -- This includes counts of posts, comments, badges, and calculated scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate AS UserLastAccessDate,
        U.WebsiteUrl,
        U.Location,
        U.AboutMe,
        U.Views AS UserProfileViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT P_Owned.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN P_Owned.PostTypeId = 1 THEN P_Owned.Id END) AS TotalQuestionsCreated,
        COUNT(DISTINCT CASE WHEN P_Owned.PostTypeId = 2 THEN P_Owned.Id END) AS TotalAnswersCreated,
        COUNT(DISTINCT C_Made.Id) AS TotalCommentsMade,
        SUM(COALESCE(P_Owned.ViewCount, 0)) AS TotalPostViewsOwned,
        SUM(COALESCE(P_Owned.Score, 0)) AS TotalPostScoreOwned,
        COUNT(DISTINCT PH_Edited.PostId) AS TotalPostsEditedByAuthor,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        -- Complex calculation for user activity score
        (U.Reputation * 0.5) + (COUNT(DISTINCT P_Owned.Id) * 2) + (COUNT(DISTINCT C_Made.Id) * 0.5) + (U.UpVotes * 0.1) AS UserActivityScore
    FROM Users U
    LEFT JOIN Posts P_Owned ON U.Id = P_Owned.OwnerUserId
    LEFT JOIN Comments C_Made ON U.Id = C_Made.UserId
    LEFT JOIN Badges B ON U.Id = B.UserId
    LEFT JOIN PostHistory PH_Edited ON U.Id = PH_Edited.UserId AND PH_Edited.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit/Rollback Body/Title/Tags
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.WebsiteUrl, U.Location, U.AboutMe, U.Views, U.UpVotes, U.DownVotes
),
PostActivitySummary AS (
    -- CTE 2: Aggregate detailed activity and metrics for each post.
    -- Includes vote counts, history event counts, and latest activity.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.OwnerUserId,
        P.AcceptedAnswerId,
        P.ParentId,
        P.Title,
        P.Tags,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.AnswerCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount,
        P.LastEditDate,
        P.LastActivityDate,
        P.ClosedDate,
        COALESCE(P.CommunityOwnedDate, '1900-01-01 00:00:00') AS CommunityOwnedDate, -- Use a default date for NULL for easier date comparisons
        -- Subqueries for specific vote and history counts
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(V.Id) FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId IN (4, 5, 6)) AS EditHistoryCount,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 10) AS CloseHistoryCount,
        (SELECT COUNT(PH.Id) FROM PostHistory PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 11) AS ReopenHistoryCount,
        (SELECT MAX(C.CreationDate) FROM Comments C WHERE C.PostId = P.Id) AS LatestCommentDate,
        (SELECT SUM(C.Score) FROM Comments C WHERE C.PostId = P.Id) AS TotalCommentScore,
        -- Correlated subquery for average score of posts linked as duplicates
        (
            SELECT AVG(P_Dup.Score)
            FROM PostLinks PL_Dup
            JOIN Posts P_Dup ON PL_Dup.RelatedPostId = P_Dup.Id
            WHERE PL_Dup.PostId = P.Id AND PL_Dup.LinkTypeId = 3
        ) AS AvgDuplicateLinkScore
    FROM Posts P
    JOIN PostTypes PT ON P.PostTypeId = PT.Id
),
PostTagging AS (
    -- CTE 3: Extract individual tags from the 'Tags' string column.
    -- Uses string manipulation and UNNEST to normalize tag data.
    SELECT
        PS.PostId,
        TRIM(UNNEST(string_to_array(SUBSTRING(PS.Tags, 2, LENGTH(PS.Tags) - 2), '><'))) AS TagName
    FROM PostActivitySummary PS
    WHERE PS.Tags IS NOT NULL AND LENGTH(PS.Tags) > 2 -- Ensure tags string is not empty or just "<>"
),
RankedActivity AS (
    -- CTE 4: Combine user and post data, apply window functions, and derive more complex ratios.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalPostsCreated,
        UE.UserActivityScore,
        UE.GoldBadges,
        UE.SilverBadges,
        UE.BronzeBadges,
        PAS.PostId,
        PAS.PostTypeName,
        PAS.Title,
        PAS.PostCreationDate,
        PAS.PostScore,
        PAS.PostViewCount,
        PAS.AnswerCount,
        PAS.PostCommentCount,
        PAS.UpVoteCount,
        PAS.DownVoteCount,
        PAS.EditHistoryCount,
        PAS.CloseHistoryCount,
        PAS.ReopenHistoryCount,
        PAS.LatestCommentDate,
        PAS.TotalCommentScore,
        PAS.AvgDuplicateLinkScore,
        -- Window function: Rank posts by score within each post type
        ROW_NUMBER() OVER (PARTITION BY PAS.PostTypeId ORDER BY PAS.PostScore DESC, PAS.PostViewCount DESC, PAS.PostCreationDate DESC) AS PostScoreRankByType,
        -- Window function: Rank users globally by reputation
        DENSE_RANK() OVER (ORDER BY UE.Reputation DESC, UE.TotalPostsCreated DESC) AS GlobalUserReputationRank,
        -- Window function: Calculate average score of posts by the same user within a rolling window of 3 posts
        AVG(PAS.PostScore) OVER (PARTITION BY UE.UserId ORDER BY PAS.PostCreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreByUser,
        -- Complex ratios for post analysis, handling division by zero with NULLIF
        CAST(PAS.UpVoteCount AS DECIMAL) / NULLIF(PAS.DownVoteCount, 0) AS UpDownVoteRatio,
        CAST(PAS.EditHistoryCount AS DECIMAL) / NULLIF(EXTRACT(DAY FROM (NOW() - PAS.PostCreationDate)), 0) AS EditsPerDaySinceCreation,
        CAST(PAS.PostScore AS DECIMAL) / NULLIF(PAS.PostViewCount, 0) AS ScorePerViewRatio,
        -- Correlated subquery: Average score of *other* questions by the same user, excluding the current post
        (
            SELECT AVG(P_Other.Score)
            FROM Posts P_Other
            WHERE P_Other.OwnerUserId = UE.UserId
              AND P_Other.Id != PAS.PostId
              AND P_Other.PostTypeId = 1 -- Only consider questions
              AND P_Other.CreationDate < PAS.PostCreationDate -- Only posts created before the current one
        ) AS AvgEarlierQuestionsScoreByAuthor,
        -- Special Post Flag: Identify posts that are community-owned, older than 2 years, and have many edits
        CASE
            WHEN PAS.CommunityOwnedDate IS NOT NULL
             AND PAS.CommunityOwnedDate < NOW() - INTERVAL '2 years'
             AND PAS.EditHistoryCount > 5
             AND PAS.PostScore > 0 -- Ensure it's not a poorly received community wiki
             THEN 'Highly_Edited_Community_Wiki'
            ELSE NULL
        END AS SpecialPostFlag,
        -- String expression: Extract the domain from the user's WebsiteUrl
        LOWER(SUBSTRING(UE.WebsiteUrl FROM '^(?:https?://)?(?:[^@\n]+@)?(?:www\.)?([^:/\n?]+)')) AS WebsiteDomain,
        -- NULL logic: Provide a default string if user location is NULL
        COALESCE(UE.Location, 'Unknown Location') AS UserLocation
    FROM UserEngagement UE
    JOIN PostActivitySummary PAS ON UE.UserId = PAS.OwnerUserId
    WHERE PAS.PostCreationDate IS NOT NULL AND PAS.PostTypeId IN (1, 2) -- Focus on Questions and Answers with creation dates
),
ControversialPosts AS (
    -- CTE 5: Identify posts that exhibit characteristics of controversy or require moderator attention.
    SELECT
        RA.PostId,
        RA.Title,
        RA.UpDownVoteRatio,
        RA.EditHistoryCount,
        RA.CloseHistoryCount,
        RA.ReopenHistoryCount
    FROM RankedActivity RA
    WHERE
        (RA.UpDownVoteRatio IS NOT NULL AND RA.UpDownVoteRatio < 0.5 AND RA.DownVoteCount > 10) -- Low up-down ratio with significant downvotes
        OR RA.CloseHistoryCount > 1 -- Closed multiple times
        OR (RA.ReopenHistoryCount > 0 AND RA.CloseHistoryCount > 0) -- Closed and reopened
        OR (RA.EditHistoryCount > 20 AND RA.PostScore < 0) -- Many edits but negative score
        OR (RA.AvgDuplicateLinkScore IS NOT NULL AND RA.AvgDuplicateLinkScore < RA.PostScore * 0.7) -- Post is much better than its linked duplicates
)
-- Main Query: Selects and combines insights from all CTEs, applies extensive filtering and aggregations.
SELECT
    RA.PostId,
    RA.PostTypeName,
    RA.Title,
    RA.PostCreationDate,
    RA.PostScore,
    RA.PostViewCount,
    RA.UpVoteCount,
    RA.DownVoteCount,
    RA.UpDownVoteRatio,
    RA.EditHistoryCount,
    RA.CloseHistoryCount,
    RA.ReopenHistoryCount,
    RA.DisplayName AS AuthorDisplayName,
    RA.Reputation AS AuthorReputation,
    RA.GlobalUserReputationRank,
    RA.PostScoreRankByType,
    RA.ScorePerViewRatio,
    RA.AvgEarlierQuestionsScoreByAuthor,
    RA.SpecialPostFlag,
    RA.WebsiteDomain,
    RA.UserLocation,
    RA.UserActivityScore,
    RA.RollingAvgPostScoreByUser,
    -- NULL logic: Indicate if a post is considered controversial
    CASE WHEN CP.PostId IS NOT NULL THEN 'Controversial' ELSE 'Standard' END AS ControversyStatus,
    -- String aggregation: List all associated tags for the post
    STRING_AGG(PTG.TagName, ', ' ORDER BY PTG.TagName) AS AssociatedTags,
    -- Subquery: Count the number of unique comments with a score > 0 for this post
    (SELECT COUNT(DISTINCT C.Id) FROM Comments C WHERE C.PostId = RA.PostId AND C.Score > 0) AS PositiveCommentsCount,
    -- Subquery: Calculate the median score of answers for a given question (only if PostTypeId is 1)
    (
        SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY A.Score)
        FROM Posts A
        WHERE A.ParentId = RA.PostId AND RA.PostTypeId = 1
    ) AS MedianAnswerScoreForQuestion
FROM RankedActivity RA
LEFT JOIN ControversialPosts CP ON RA.PostId = CP.PostId
LEFT JOIN PostTagging PTG ON RA.PostId = PTG.PostId
WHERE
    RA.Reputation > 5000 -- Filter for users with significant reputation
    AND RA.PostCreationDate > NOW() - INTERVAL '3 years' -- Only analyze posts from the last 3 years
    AND RA.PostViewCount > 1000 -- Only highly viewed posts
    AND (
        (RA.PostTypeName = 'Question' AND RA.PostScore > 20 AND RA.AnswerCount >= 2) -- High-quality questions
        OR (RA.PostTypeName = 'Answer' AND RA.PostScore > 10 AND RA.EditHistoryCount <= 5) -- Solid, relatively stable answers
    )
    -- String expression and complex predicate: Title contains specific keywords, case-insensitive
    AND (LOWER(RA.Title) LIKE '%performance%' OR LOWER(RA.Title) LIKE '%optimization%' OR LOWER(RA.Title) LIKE '%scalable%' OR LOWER(RA.Title) LIKE '%benchmark%')
    AND RA.PostScoreRankByType <= 50 -- Limit to top 50 posts by score within their type
    AND RA.EditsPerDaySinceCreation IS NOT NULL -- Exclude posts created today (would have 0 days for ratio)
    AND RA.AvgEarlierQuestionsScoreByAuthor IS NOT NULL -- Ensure there are earlier questions to compare
GROUP BY
    RA.PostId, RA.PostTypeName, RA.Title, RA.PostCreationDate, RA.PostScore, RA.PostViewCount,
    RA.UpVoteCount, RA.DownVoteCount, RA.UpDownVoteRatio, RA.EditHistoryCount, RA.CloseHistoryCount,
    RA.ReopenHistoryCount, RA.DisplayName, RA.Reputation, RA.GlobalUserReputationRank,
    RA.PostScoreRankByType, RA.ScorePerViewRatio, RA.AvgEarlierQuestionsScoreByAuthor,
    RA.SpecialPostFlag, RA.WebsiteDomain, RA.UserLocation, RA.UserActivityScore,
    RA.RollingAvgPostScoreByUser, CP.PostId, RA.PostTypeId -- Group by PostTypeId for MedianAnswerScoreForQuestion
HAVING
    COUNT(PTG.TagName) >= 2 -- Posts must have at least two tags
    AND SUM(CASE WHEN PTG.TagName IN ('sql', 'database-performance', 'query-optimization', 'benchmarking', 'big-data') THEN 1 ELSE 0 END) >= 1 -- Must have at least one specific performance-related tag
    AND (AVG(RA.PostScore) > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = RA.PostTypeId AND CreationDate > NOW() - INTERVAL '3 years')) -- Post score is above overall average for its type
ORDER BY
    RA.GlobalUserReputationRank ASC, RA.PostScore DESC, RA.PostCreationDate DESC
LIMIT 200;
