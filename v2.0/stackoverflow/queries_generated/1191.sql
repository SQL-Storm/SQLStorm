-- {"query": "1191.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3108} 

WITH UserEngagementSummary AS (
    -- CTE 1: Summarize user activity, reputation, and derived metrics
    -- Includes users who might not have posts or comments using LEFT JOINs.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.Views AS UserProfileViews,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionsAsked,
        COALESCE(SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswersProvided,
        COALESCE(COUNT(DISTINCT P.Id), 0) AS TotalPostsCreated,
        COALESCE(COUNT(DISTINCT C.Id), 0) AS TotalCommentsMade,
        COALESCE(COUNT(DISTINCT B.Id), 0) AS TotalBadgesEarned,
        AVG(CAST(P.Score AS NUMERIC)) FILTER (WHERE P.Score IS NOT NULL) AS AveragePostScore,
        EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / (60 * 60 * 24) AS DaysActiveSinceCreation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    WHERE U.Reputation > 500 -- Filter out very low reputation users
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
),
PostPerformanceMetrics AS (
    -- CTE 2: Detailed post performance metrics, including window functions and correlated subqueries
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        PT.Name AS PostTypeName,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditDate, -- Use CreationDate if LastEditDate is NULL
        RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankByScoreAndViews,
        NTILE(5) OVER (ORDER BY P.CreationDate) AS CreationDateQuintile,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'), 1) AS NumberOfTags,
        CAST(P.Score AS NUMERIC) / NULLIF(P.ViewCount, 0) AS ScorePerViewRatio,
        (SELECT COUNT(DISTINCT V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVoteCount, -- Correlated subquery for upvotes
        (SELECT COUNT(DISTINCT V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVoteCount, -- Correlated subquery for downvotes
        CASE
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Not Accepted'
        END AS AnswerStatus
    FROM Posts AS P
    INNER JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    WHERE P.CreationDate BETWEEN '2022-01-01' AND '2023-12-31'
      AND P.PostTypeId IN (1, 2) -- Focus on Questions and Answers
      AND P.ViewCount > 100 AND P.Score IS NOT NULL
),
PostHistoryDetails AS (
    -- CTE 3: Aggregate post history events, including specific types and string aggregation for close reasons
    SELECT
        PH.PostId,
        COUNT(PH.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditEvents, -- Edit Title, Body, Tags
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        MAX(PH.CreationDate) AS LastHistoryActivity,
        STRING_AGG(DISTINCT CRT.Name, '; ' ORDER BY CRT.Name) FILTER (WHERE PH.PostHistoryTypeId = 10 AND PH.Comment IS NOT NULL) AS DistinctCloseReasons,
        MAX(LENGTH(PH.Text)) AS MaxHistoryTextLength -- String expression for text length
    FROM PostHistory AS PH
    LEFT JOIN CloseReasonTypes AS CRT ON CAST(PH.Comment AS SMALLINT) = CRT.Id
    WHERE PH.CreationDate > '2022-06-01'
    GROUP BY PH.PostId
),
LinkedPostAggregates AS (
    -- CTE 4: Summarize linked and duplicate posts
    SELECT
        PL.PostId,
        COUNT(DISTINCT PL.RelatedPostId) AS TotalRelatedPosts,
        SUM(CASE WHEN PL.LinkTypeId = 1 THEN 1 ELSE 0 END) AS DirectLinksOutCount,
        SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksOutCount
    FROM PostLinks AS PL
    WHERE PL.CreationDate > '2022-01-01'
    GROUP BY PL.PostId
),
-- CTE 5 & 6 & 7 for set operator demonstration: Identify popular tags based on different criteria
HighScoringTags AS (
    -- Tags from posts with high average scores
    SELECT DISTINCT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.PostTypeId = 1
    GROUP BY TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')))
    HAVING AVG(CAST(P.Score AS NUMERIC)) > 10
),
HighlyViewedTags AS (
    -- Tags from posts with very high view counts
    SELECT DISTINCT
        TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.PostTypeId = 1 AND P.ViewCount > 50000
),
CommonPopularTags AS (
    -- INTERSECT to find tags that are both high-scoring and highly-viewed
    SELECT TagName FROM HighScoringTags
    INTERSECT
    SELECT TagName FROM HighlyViewedTags
),
TagPerformanceBreakdown AS (
    -- CTE 8: Detailed tag performance, filtered by CommonPopularTags and using DENSE_RANK
    SELECT
        TFP.TagName,
        SUM(PPM.PostScore) AS TaggedPostsTotalScore,
        COUNT(PPM.PostId) AS TaggedPostsCount,
        AVG(PPM.ScorePerViewRatio) FILTER (WHERE PPM.ScorePerViewRatio IS NOT NULL) AS AvgTagScorePerView,
        DENSE_RANK() OVER (ORDER BY SUM(PPM.PostScore) DESC, COUNT(PPM.PostId) DESC) AS TagScoreRankOverall
    FROM (
        SELECT P.Id AS PostId, TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))) AS TagName
        FROM Posts AS P
        WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2
    ) AS TFP
    INNER JOIN PostPerformanceMetrics AS PPM ON TFP.PostId = PPM.PostId
    INNER JOIN CommonPopularTags AS CPT ON TFP.TagName = CPT.TagName -- Filter based on set operator result
    GROUP BY TFP.TagName
    HAVING COUNT(PPM.PostId) > 100 -- Only consider tags with significant usage
)
-- Main Query: Joins all CTEs and applies complex filtering and final calculations
SELECT
    UES.UserId,
    UES.DisplayName,
    UES.Reputation,
    UES.UserProfileViews,
    UES.QuestionsAsked,
    UES.AnswersProvided,
    UES.AveragePostScore,
    PPM.PostId,
    PPM.PostTypeName,
    PPM.PostScore,
    PPM.ViewCount,
    PPM.AnswerCount,
    PPM.CommentCount,
    PPM.FavoriteCount,
    PPM.Title,
    PPM.NumberOfTags,
    PPM.RankByScoreAndViews,
    PPM.CreationDateQuintile,
    COALESCE(PPM.ScorePerViewRatio, 0.0) AS NormalizedScorePerView, -- NULL handling
    PPM.UpVoteCount,
    PPM.DownVoteCount,
    PHD.TotalHistoryEvents,
    PHD.TotalEditEvents,
    PHD.TotalCloseEvents,
    PHD.DistinctCloseReasons,
    PHD.MaxHistoryTextLength,
    LPA.TotalRelatedPosts,
    LPA.DirectLinksOutCount,
    LPA.DuplicateLinksOutCount,
    TPB.TagName AS MostRelevantTagName,
    TPB.TaggedPostsTotalScore AS RelevantTagScore,
    TPB.TaggedPostsCount AS RelevantTagPostCount,
    TPB.AvgTagScorePerView AS RelevantTagAvgScorePerView,
    TPB.TagScoreRankOverall AS RelevantTagRank,
    (SELECT MAX(U_LOC.Reputation)
     FROM Users AS U_LOC
     WHERE U_LOC.Location IS NOT NULL
       AND UES.Location IS NOT NULL
       AND U_LOC.Location LIKE '%' || UES.Location || '%' -- String matching for location similarity
       AND U_LOC.Id <> UES.UserId
    ) AS MaxReputationInSameApproxLocation, -- Another correlated subquery
    CASE
        WHEN UES.Reputation > 20000 AND PPM.PostScore > 100 AND PPM.AnswerStatus = 'Accepted' THEN 'Elite Contributor & High-Impact Post'
        WHEN UES.Reputation > 5000 AND PPM.PostScore > 50 THEN 'Significant Contributor & Popular Post'
        WHEN UES.Reputation > 1000 AND PPM.PostScore > 10 THEN 'Active Contributor'
        ELSE 'Emerging Contributor'
    END AS ContributionTier,
    TO_CHAR(PPM.EffectiveLastEditDate, 'YYYY-MM-DD HH24:MI:SS') AS FormattedLastEditDate, -- Date formatting
    UPPER(LEFT(COALESCE(UES.DisplayName, 'UNKNOWN'), 1)) AS FirstLetterOfDisplayName
FROM UserEngagementSummary AS UES
INNER JOIN PostPerformanceMetrics AS PPM ON UES.UserId = PPM.OwnerUserId
LEFT JOIN PostHistoryDetails AS PHD ON PPM.PostId = PHD.PostId
LEFT JOIN LinkedPostAggregates AS LPA ON PPM.PostId = LPA.PostId
LEFT JOIN (
    -- Subquery to get one relevant tag per post for joining to TagPerformanceBreakdown
    SELECT
        TFP_sub.PostId,
        MIN(TFP_sub.TagName) AS TagName -- Just pick one if multiple tags match CommonPopularTags
    FROM (
        SELECT P_sub.Id AS PostId, TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(P_sub.Tags, 2, LENGTH(P_sub.Tags) - 2), '><'))) AS TagName
        FROM Posts AS P_sub
        WHERE P_sub.Tags IS NOT NULL AND LENGTH(P_sub.Tags) > 2
    ) AS TFP_sub
    INNER JOIN CommonPopularTags AS CPT_sub ON TFP_sub.TagName = CPT_sub.TagName
    GROUP BY TFP_sub.PostId
) AS PostPrimaryTag ON PPM.PostId = PostPrimaryTag.PostId
LEFT JOIN TagPerformanceBreakdown AS TPB ON PostPrimaryTag.TagName = TPB.TagName
WHERE PPM.RankByScoreAndViews <= 200 -- Only consider top-ranked posts within their type
  AND UES.DaysActiveSinceCreation >= 730 -- Users active for at least 2 years
  AND (PHD.TotalCloseEvents = 0 OR PHD.DistinctCloseReasons LIKE '%Duplicate%' OR PHD.DistinctCloseReasons IS NULL) -- Posts not closed, or closed as duplicate
  AND PPM.UpVoteCount > PPM.DownVoteCount * 2 -- Significantly more upvotes than downvotes
  AND PPM.NumberOfTags BETWEEN 2 AND 5 -- Posts with a moderate number of tags
  AND UES.AveragePostScore IS NOT NULL
  AND UES.Location IS NOT NULL -- Only users with a specified location
ORDER BY UES.Reputation DESC, PPM.PostScore DESC, TPB.TagScoreRankOverall ASC, PPM.CreationDateQuintile DESC
LIMIT 1000;
