-- {"query": "1736.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2345} 

WITH UserActivitySummary AS (
    -- Summarizes user activity, including total posts, comments, and specific vote types received on their posts.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts, -- UpMod
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts, -- DownMod
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceivedOnPosts, -- Favorite
        COALESCE(AVG(P.Score), 0) AS AvgPostScore,
        SUM(CASE WHEN U.AccountId IS NULL THEN 1 ELSE 0 END) AS HasNullAccountId
    FROM
        Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId -- Votes on posts owned by the user
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
PostEngagementMetrics AS (
    -- Calculates various engagement metrics for posts, including specific vote types, comment count, and accepted answer status.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.CommentCount AS PostCommentCount,
        P.FavoriteCount AS PostFavoriteCount,
        P.LastActivityDate,
        P.LastEditDate,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesCount,
        SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesCount,
        SUM(CASE WHEN V.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotesCount,
        MAX(CASE WHEN P.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS HasAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.Score DESC, P.CreationDate DESC) AS PostRankByOwnerScore,
        DENSE_RANK() OVER (ORDER BY P.ViewCount DESC, P.Score DESC) AS GlobalViewRank
    FROM
        Posts P
    LEFT JOIN Votes V ON P.Id = V.PostId
    GROUP BY
        P.Id, P.PostTypeId, P.CreationDate, P.Score, P.ViewCount, P.CommentCount, P.FavoriteCount, P.LastActivityDate, P.LastEditDate, P.OwnerUserId, P.Title, P.Tags
),
TagPerformance AS (
    -- Analyzes performance of tags based on associated questions.
    -- Using string_to_array from description, adapting it for general SQL
    SELECT
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
        COUNT(DISTINCT P.Id) AS TotalQuestionsWithTag,
        AVG(P.Score) AS AvgTagQuestionScore,
        SUM(P.ViewCount) AS TotalTagViewCount,
        COUNT(DISTINCT P.OwnerUserId) AS UniqueTagOwners
    FROM
        Posts P
    WHERE
        P.PostTypeId = 1 -- Only questions have tags in this format
        AND P.Tags IS NOT NULL
        AND LENGTH(TRIM(P.Tags)) > 2 -- Ensure tags are not just '<>'
    GROUP BY
        TRIM(unnest(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))
    HAVING
        COUNT(DISTINCT P.Id) > 10 -- Only consider tags with a reasonable number of questions
),
PostHistoryBodyDiffs AS (
    -- Calculates the length difference between consecutive body edits for posts.
    SELECT
        PH.PostId,
        PH.CreationDate AS HistoryDate,
        PH.Text AS CurrentBodyText,
        LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousBodyText,
        LENGTH(PH.Text) - LENGTH(LAG(PH.Text, 1, '') OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate)) AS BodyLengthChange
    FROM
        PostHistory PH
    WHERE
        PH.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
),
HighlyEngagedPosts AS (
    SELECT PostId FROM PostEngagementMetrics WHERE UpvotesCount > 50 AND PostCommentCount > 10
),
HighlyReputedUsers AS (
    SELECT UserId FROM UserActivitySummary WHERE Reputation > 10000 AND TotalPosts > 50
)
-- Main query combining results from CTEs and adding more complexity
SELECT
    UAS.UserId,
    UAS.DisplayName AS UserDisplayName,
    UAS.Reputation,
    UAS.TotalPosts,
    UAS.TotalQuestions,
    UAS.TotalAnswers,
    UAS.TotalCommentsMade,
    UAS.AvgPostScore,
    UAS.TotalUpvotesReceivedOnPosts,
    PEM.PostId,
    PEM.Title AS PostTitle,
    PEM.PostScore AS CurrentPostScore,
    PEM.ViewCount AS CurrentPostViewCount,
    PEM.UpvotesCount AS PostUpvoteCount,
    PEM.DownvotesCount AS PostDownvoteCount,
    PEM.PostFavoriteCount,
    PEM.HasAcceptedAnswer,
    PEM.PostRankByOwnerScore,
    PEM.GlobalViewRank,
    PHBD.BodyLengthChange AS LastBodyEditChange,
    TP.TagName AS TopPerformingTag,
    TP.AvgTagQuestionScore,
    TP.TotalTagViewCount,
    TP.UniqueTagOwners,
    PL.RelatedPostId AS LinkedPostId,
    LT.Name AS LinkTypeName,
    CASE
        WHEN UAS.Reputation > 10000 AND PEM.PostScore > 50 THEN 'High-Impact User & Post'
        WHEN UAS.Reputation BETWEEN 1000 AND 10000 AND PEM.ViewCount > 5000 THEN 'Mid-Tier User, Popular Post'
        WHEN UAS.HasNullAccountId > 0 THEN 'User with Missing Account Info' -- NULL logic example
        ELSE 'Regular Activity'
    END AS UserPostSegment,
    -- Correlated Subquery: Check if the post's owner has any related posts linked by a 'Duplicate' link type,
    -- AND if that duplicate post also has a significantly higher score and is owned by a highly reputed user.
    (
        SELECT
            COUNT(DISTINCT PL_Inner.RelatedPostId)
        FROM
            PostLinks PL_Inner
        INNER JOIN Posts P_Inner ON PL_Inner.RelatedPostId = P_Inner.Id
        WHERE
            PL_Inner.PostId = PEM.PostId
            AND PL_Inner.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate')
            AND P_Inner.Score > PEM.PostScore * 1.5
            AND P_Inner.OwnerUserId IN (SELECT UserId FROM HighlyReputedUsers)
    ) AS CountOfHigherScoringDuplicates,
    -- String Expression: Calculate a hash-like value for the post title by combining its length and specific character counts
    (LENGTH(PEM.Title) * 100 +
     LENGTH(REPLACE(LOWER(PEM.Title), 'how', '')) * 50 +
     LENGTH(REPLACE(LOWER(PEM.Title), 'what', '')) * 25 +
     COALESCE(NULLIF(LENGTH(REPLACE(LOWER(PEM.Title), '?', '')), LENGTH(LOWER(PEM.Title))), 0) * 10) AS TitleComplexityScore
FROM
    UserActivitySummary UAS
INNER JOIN PostEngagementMetrics PEM ON UAS.UserId = PEM.OwnerUserId
LEFT JOIN PostHistoryBodyDiffs PHBD ON PEM.PostId = PHBD.PostId
LEFT JOIN PostLinks PL ON PEM.PostId = PL.PostId
LEFT JOIN LinkTypes LT ON PL.LinkTypeId = LT.Id
LEFT JOIN (
    SELECT
        TagName,
        AvgTagQuestionScore,
        TotalTagViewCount,
        UniqueTagOwners,
        ROW_NUMBER() OVER (ORDER BY AvgTagQuestionScore DESC, TotalTagViewCount DESC) AS TagRank -- For selecting a 'top' tag
    FROM TagPerformance
) TP ON PEM.Tags LIKE '%<' || TP.TagName || '>%' AND TP.TagRank = 1 -- Only join with the overall top tag for demonstration
WHERE
    UAS.Reputation > 500
    AND PEM.PostTypeId = 1 -- Focus on questions
    AND PEM.PostScore > 5
    AND PEM.CreationDate BETWEEN '2020-01-01' AND '2022-12-31'
    AND (
        (PEM.ViewCount > 10000 AND PEM.UpvotesCount > 100)
        OR (PEM.PostFavoriteCount > 50 AND PEM.PostCommentCount > 20)
    )
    AND UAS.DisplayName IS NOT NULL -- NULL logic
    AND PEM.PostId IN (SELECT PostId FROM HighlyEngagedPosts) -- Set operator applied via IN (conceptually)
ORDER BY
    UAS.Reputation DESC,
    PEM.GlobalViewRank ASC,
    PHBD.BodyLengthChange DESC NULLS LAST -- NULL logic with ordering
LIMIT 500;
