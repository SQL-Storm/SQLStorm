-- {"query": "1339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2820} 
WITH UserEngagement AS (
    -- Aggregates various user-level metrics including post counts, scores, and badge statistics.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT P.Id) AS TotalPostsAuthored,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAuthored,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersAuthored,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreReceived,
        COALESCE(SUM(P.ViewCount), 0) AS TotalPostViewsReceived,
        AVG(CASE WHEN P.PostTypeId = 2 THEN P.Score ELSE NULL END) AS AvgAnswerScore,
        MAX(P.CreationDate) AS LastPostDate,
        COUNT(DISTINCT B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes
),
PostHistoricalMetrics AS (
    -- Analyzes post history for edit counts, close events, and relevant dates.
    SELECT
        PH.PostId,
        COUNT(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount, -- Title, Body, Tags edits
        COUNT(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVoteCount,
        MAX(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN PH.CreationDate ELSE NULL END) AS LastEditHistoryDate,
        MIN(CASE WHEN PH.PostHistoryTypeId = 10 THEN PH.CreationDate ELSE NULL END) AS FirstCloseDate
    FROM PostHistory AS PH
    GROUP BY PH.PostId
),
UserTopTagsRefined AS (
    -- Identifies the top 3 most impactful tags for each user based on post scores.
    SELECT
        UserId,
        STRING_AGG(TagName, ', ' ORDER BY TagScore DESC) AS Top3Tags
    FROM (
        SELECT
            P.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><'))) AS TagName,
            SUM(P.Score) AS TagScore,
            COUNT(P.Id) AS TagCount,
            ROW_NUMBER() OVER(PARTITION BY P.OwnerUserId ORDER BY SUM(P.Score) DESC, COUNT(P.Id) DESC) AS rn
        FROM Posts AS P
        WHERE P.OwnerUserId IS NOT NULL AND P.Tags IS NOT NULL AND P.PostTypeId = 1
        GROUP BY P.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags)-2), '><')))
    ) AS TaggedPosts
    WHERE rn <= 3
    GROUP BY UserId
),
PostCommentSummary AS (
    -- Summarizes comments for posts, including basic sentiment analysis based on keywords.
    SELECT
        C.PostId,
        COUNT(C.Id) AS TotalComments,
        AVG(C.Score) AS AvgCommentScore,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%thank%' OR LOWER(C.Text) LIKE '%appreciate%' THEN 1 ELSE 0 END) AS ThankYouComments,
        SUM(CASE WHEN LOWER(C.Text) LIKE '%bug%' OR LOWER(C.Text) LIKE '%error%' THEN 1 ELSE 0 END) AS IssueComments
    FROM Comments AS C
    GROUP BY C.PostId
),
BasePostAnalysis AS (
    -- Combines user engagement, post details, historical metrics, and comment summaries.
    -- Includes various complex calculations, window functions, and correlated subqueries.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalPostsAuthored,
        UE.TotalQuestionsAuthored,
        UE.TotalAnswersAuthored,
        UE.TotalPostScoreReceived,
        UE.TotalPostViewsReceived,
        UE.AvgAnswerScore,
        UE.TotalBadges,
        UE.GoldBadges,
        UE.SilverBadges,
        UTT.Top3Tags,
        P.Id AS PostId,
        PT.Name AS PostTypeName,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount AS PostViewCount,
        P.CommentCount AS PostBuiltinCommentCount,
        COALESCE(PCS.TotalComments, 0) AS ActualTotalComments,
        PCS.AvgCommentScore,
        COALESCE(PHM.EditCount, 0) AS PostEditCount,
        COALESCE(PHM.CloseVoteCount, 0) AS PostCloseVoteCount,
        PHM.FirstCloseDate,
        PHM.LastEditHistoryDate,
        P.ClosedDate IS NOT NULL AS IsPostClosedByCommunity,
        P.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned,
        CASE
            WHEN P.ViewCount > 10000 AND P.Score > 50 THEN 'Viral'
            WHEN P.ViewCount > 1000 AND P.Score > 10 THEN 'Popular'
            WHEN P.Score < 0 THEN 'PoorlyReceived'
            ELSE 'Normal'
        END AS PostPopularityCategory,
        P.Title AS PostTitle,
        P.Tags AS PostRawTags,
        CASE
            WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        -- Window functions for ranking and trend analysis
        RANK() OVER (PARTITION BY UE.UserId ORDER BY P.Score DESC, P.ViewCount DESC) AS RankOfPostByUser,
        NTILE(5) OVER (ORDER BY UE.Reputation DESC, UE.TotalPostScoreReceived DESC) AS UserReputationQuintile,
        LAG(P.CreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY P.CreationDate) AS PreviousPostDate,
        (P.CreationDate - LAG(P.CreationDate, 1, UE.UserCreationDate) OVER (PARTITION BY UE.UserId ORDER BY P.CreationDate)) AS DaysSincePreviousPost,
        AVG(P.Score) OVER (PARTITION BY UE.UserId ORDER BY P.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS RollingAvgPostScoreLast3,
        -- Correlated subqueries to count votes after post creation
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 2 AND V.CreationDate >= P.CreationDate) AS UpVoteCountAfterCreation,
        (SELECT COUNT(V.Id) FROM Votes AS V WHERE V.PostId = P.Id AND V.VoteTypeId = 3 AND V.CreationDate >= P.CreationDate) AS DownVoteCountAfterCreation,
        -- Complex calculation with NULL logic
        COALESCE(P.AnswerCount, 0) + COALESCE(PCS.TotalComments, 0) + COALESCE(PHM.EditCount, 0) AS TotalPostActivitySignals,
        NULLIF(CAST(P.Score AS numeric), 0) * (P.ViewCount / NULLIF(CAST(P.AnswerCount AS numeric), 0.0)) AS EngagementRatio
    FROM UserEngagement AS UE
    INNER JOIN Posts AS P ON UE.UserId = P.OwnerUserId
    LEFT JOIN PostTypes AS PT ON P.PostTypeId = PT.Id
    LEFT JOIN PostHistoricalMetrics AS PHM ON P.Id = PHM.PostId
    LEFT JOIN PostCommentSummary AS PCS ON P.Id = PCS.PostId
    LEFT JOIN UserTopTagsRefined AS UTT ON UE.UserId = UTT.UserId
    WHERE
        P.OwnerUserId IS NOT NULL -- Ensure owner exists
        AND NOT EXISTS ( -- Correlated subquery to exclude deleted posts
            SELECT 1
            FROM PostHistory AS PH_Sub
            WHERE PH_Sub.PostId = P.Id
            AND PH_Sub.PostHistoryTypeId = 12 -- Post Deleted
            AND PH_Sub.CreationDate > P.CreationDate
        )
)
-- Combines two distinct analytical groups using UNION ALL for comparative benchmarking.
-- Group 1: High-reputation users with recent, popular, and answered SQL-related questions.
SELECT
    'HighRep_PopularQuestions' AS AnalysisGroup,
    BPA.UserId,
    BPA.DisplayName,
    BPA.Reputation,
    BPA.PostId,
    BPA.PostTitle,
    BPA.PostTypeName,
    BPA.PostCreationDate,
    BPA.PostScore,
    BPA.PostViewCount,
    BPA.PostPopularityCategory,
    BPA.Top3Tags,
    BPA.IsPostClosedByCommunity,
    BPA.HasAcceptedAnswer,
    BPA.RollingAvgPostScoreLast3,
    BPA.UpVoteCountAfterCreation,
    BPA.DaysSincePreviousPost
FROM BasePostAnalysis AS BPA
WHERE
    BPA.Reputation > 10000
    AND BPA.PostTypeName = 'Question'
    AND BPA.PostCreationDate BETWEEN '2023-01-01' AND '2023-12-31'
    AND BPA.PostPopularityCategory = 'Viral'
    AND BPA.IsPostClosedByCommunity = FALSE
    AND BPA.HasAcceptedAnswer = TRUE
    AND BPA.Top3Tags LIKE '%sql%' -- String expression
    AND BPA.DaysSincePreviousPost IS NOT NULL AND EXTRACT(DAY FROM BPA.DaysSincePreviousPost) < 30 -- Frequent posting
ORDER BY
    BPA.Reputation DESC,
    BPA.PostScore DESC,
    BPA.PostCreationDate DESC
LIMIT 500

UNION ALL

-- Group 2: Mid-tier users with well-received answers to older 'performance'-tagged questions, excluding users with no location.
SELECT
    'MidRep_GoodAnswers' AS AnalysisGroup,
    BPA.UserId,
    BPA.DisplayName,
    BPA.Reputation,
    BPA.PostId,
    BPA.PostTitle,
    BPA.PostTypeName,
    BPA.PostCreationDate,
    BPA.PostScore,
    BPA.PostViewCount,
    BPA.PostPopularityCategory,
    BPA.Top3Tags,
    BPA.IsPostClosedByCommunity,
    BPA.HasAcceptedAnswer,
    BPA.RollingAvgPostScoreLast3,
    BPA.UpVoteCountAfterCreation,
    BPA.DaysSincePreviousPost
FROM BasePostAnalysis AS BPA
WHERE
    BPA.Reputation BETWEEN 1000 AND 5000
    AND BPA.PostTypeName = 'Answer'
    AND BPA.PostCreationDate BETWEEN '2021-01-01' AND '2022-12-31'
    AND BPA.PostScore > 5
    AND BPA.PostEditCount < 5 -- Not too many edits
    AND BPA.TotalPostActivitySignals > 5 -- Indicates engagement
    AND BPA.UserId NOT IN (SELECT U.Id FROM Users U WHERE U.Location IS NULL) -- NULL logic in subquery
    AND BPA.PostRawTags LIKE '%<performance>%' -- String expression
ORDER BY
    BPA.AvgAnswerScore DESC,
    BPA.Reputation DESC,
    BPA.PostCreationDate ASC
LIMIT 500;