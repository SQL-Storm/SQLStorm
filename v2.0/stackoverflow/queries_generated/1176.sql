-- {"query": "1176.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2986} 

WITH UserBaseStats AS (
    -- Gathers core user information, their posts, comments, and badge counts
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotes,
        U.DownVotes AS UserDownVotes,
        U.LastAccessDate,
        -- Determines the user's latest activity across posts, comments, or direct access
        COALESCE(MAX(P.LastActivityDate), MAX(C.CreationDate), U.LastAccessDate) AS LatestActivityDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 1) AS GoldBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 2) AS SilverBadges,
        COUNT(DISTINCT B.Id) FILTER (WHERE B.Class = 3) AS BronzeBadges
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Badges AS B ON U.Id = B.UserId
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.Views, U.UpVotes, U.DownVotes, U.LastAccessDate
),
PostActivityMetrics AS (
    -- Analyzes individual post metrics, history, and tag presence
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        COALESCE(P.LastEditDate, P.CreationDate) AS EffectiveLastEditOrCreationDate,
        -- Correlated Subquery: Retrieves the original title of a post from its history
        (SELECT PH.Text FROM PostHistory AS PH WHERE PH.PostId = P.Id AND PH.PostHistoryTypeId = 1 ORDER BY PH.CreationDate ASC LIMIT 1) AS OriginalTitle,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS TotalEdits,
        MAX(PH.CreationDate) AS LastHistoryEditDate,
        (CURRENT_TIMESTAMP - MAX(PH.CreationDate)) AS TimeSinceLastHistoryEdit, -- Interval calculation
        P.Tags,
        -- String expression and conditional logic to check for specific tags
        CASE
            WHEN P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%' OR P.Tags LIKE '%<postgresql>%' OR P.Tags LIKE '%<mysql>%' THEN TRUE
            ELSE FALSE
        END AS ContainsSqlOrDatabaseTag,
        -- Window function: Ranks posts within their type by quality metrics
        DENSE_RANK() OVER (PARTITION BY P.PostTypeId ORDER BY P.Score DESC, P.ViewCount DESC, P.CommentCount DESC) AS PostRankByQuality
    FROM Posts AS P
    LEFT JOIN PostHistory AS PH ON P.Id = PH.PostId
    WHERE P.OwnerUserId IS NOT NULL -- Focus on user-owned posts
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.ClosedDate, P.LastEditDate, P.Tags
),
UserQualityMetrics AS (
    -- Aggregates post-level metrics back to user level
    SELECT
        UBS.UserId,
        UBS.DisplayName,
        UBS.Reputation,
        UBS.TotalPosts,
        UBS.TotalQuestions,
        UBS.TotalAnswers,
        UBS.TotalComments,
        UBS.GoldBadges,
        UBS.SilverBadges,
        UBS.BronzeBadges,
        SUM(PAM.Score) AS OverallPostsScore,
        AVG(PAM.Score) FILTER (WHERE PAM.PostTypeId IN (1,2)) AS AvgPostScore,
        SUM(CASE WHEN PAM.PostTypeId = 1 THEN PAM.ViewCount ELSE 0 END) AS TotalQuestionViewCount,
        SUM(PAM.FavoriteCount) AS TotalFavoriteCounts,
        COUNT(PAM.PostId) FILTER (WHERE PAM.ClosedDate IS NOT NULL AND PAM.PostTypeId = 1) AS ClosedQuestionCount,
        COUNT(PAM.PostId) FILTER (WHERE PAM.ContainsSqlOrDatabaseTag) AS PostsWithSpecificTags,
        MAX(PAM.Score) AS MaxPostScoreByThisUser,
        -- Identifies a user's top-quality post (arbitrarily picking one if multiple have rank 1)
        MAX(PAM.PostId) FILTER (WHERE PAM.PostRankByQuality = 1) AS TopQualityPostId,
        AVG(PAM.TotalEdits) FILTER (WHERE PAM.PostTypeId IN (1,2)) AS AvgEditsPerPost,
        -- Window function: Assigns a percentile rank to users based on their overall post score
        NTILE(100) OVER (ORDER BY SUM(PAM.Score) DESC, COUNT(PAM.PostId) DESC) AS UserOverallScorePercentile
    FROM UserBaseStats AS UBS
    LEFT JOIN PostActivityMetrics AS PAM ON UBS.UserId = PAM.OwnerUserId
    GROUP BY
        UBS.UserId, UBS.DisplayName, UBS.Reputation, UBS.TotalPosts, UBS.TotalQuestions,
        UBS.TotalAnswers, UBS.TotalComments, UBS.GoldBadges, UBS.SilverBadges, UBS.BronzeBadges
),
AdvancedUserMetrics AS (
    -- Calculates advanced derived metrics and uses more window functions for comparative analysis
    SELECT
        UQM.UserId,
        UQM.DisplayName,
        UQM.Reputation,
        UQM.TotalPosts,
        UQM.TotalQuestions,
        UQM.TotalAnswers,
        UQM.TotalComments,
        UQM.AvgPostScore,
        UQM.TotalQuestionViewCount,
        UQM.ClosedQuestionCount,
        UQM.PostsWithSpecificTags,
        UQM.GoldBadges + UQM.SilverBadges + UQM.BronzeBadges AS TotalBadges,
        -- Complex calculation: Reputation normalized by total posts
        ROUND(UQM.Reputation * 1.0 / NULLIF(UQM.TotalPosts, 0), 2) AS ReputationPerPost,
        -- Complex calculation: Average post score relative to comment count
        ROUND(UQM.AvgPostScore * 1.0 / NULLIF(UQM.TotalComments, 0), 2) AS PostScorePerCommentRatio,
        ROUND(UQM.TotalQuestionViewCount * 1.0 / NULLIF(UQM.TotalQuestions, 0), 2) AS AvgViewsPerQuestion,
        -- Conditional calculation: Percentage of closed questions
        CASE
            WHEN UQM.TotalQuestions > 0 THEN ROUND(UQM.ClosedQuestionCount * 100.0 / UQM.TotalQuestions, 2)
            ELSE 0
        END AS ClosedQuestionPercentage,
        UQM.UserOverallScorePercentile,
        -- Window functions for ranking and distribution
        RANK() OVER (ORDER BY UQM.Reputation DESC, UQM.TotalPosts DESC) AS OverallUserRank,
        NTILE(4) OVER (ORDER BY UQM.Reputation DESC) AS ReputationQuartile,
        CUME_DIST() OVER (ORDER BY UQM.TotalPosts DESC) AS CumulativePostDistribution,
        -- Window function: Compares reputation to the user ranked directly above
        LAG(UQM.Reputation, 1, 0) OVER (ORDER BY UQM.Reputation DESC) AS PreviousReputationInRank,
        -- Correlated Subquery: Counts duplicates for the user's top quality post
        (SELECT COUNT(DISTINCT PL.RelatedPostId) FROM PostLinks AS PL WHERE PL.PostId = UQM.TopQualityPostId AND PL.LinkTypeId = 3) AS DuplicatedPostCountForTopPost,
        -- String expression: Concatenates user info
        'User ' || COALESCE(UQM.DisplayName, 'N/A') || ' (ID: ' || UQM.UserId || ')' AS UserIdentifierString,
        -- Complex calculation involving date functions: Reputation growth rate per day since creation
        UQM.Reputation / NULLIF((EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - (SELECT UserCreationDate FROM UserBaseStats WHERE UserId = UQM.UserId))) / (3600 * 24)), 0) AS ReputationPerDaySinceCreation
    FROM UserQualityMetrics AS UQM
    WHERE UQM.TotalPosts > 0 OR UQM.TotalComments > 0
)
-- Main query: Combines two distinct analytical perspectives using UNION ALL
-- Perspective 1: Top Quality Contributors based on multiple engagement and performance metrics
SELECT
    'Top Quality Contributor' AS AnalysisCategory,
    AUM.UserId,
    AUM.UserIdentifierString,
    AUM.Reputation,
    AUM.TotalPosts,
    AUM.AvgPostScore,
    AUM.AvgViewsPerQuestion,
    AUM.TotalBadges,
    AUM.OverallUserRank,
    AUM.ReputationPerPost,
    AUM.PostScorePerCommentRatio,
    NULL AS ClosedQuestionPercentage, -- NULL for this category
    NULL AS DuplicatedPostCount,    -- NULL for this category
    AUM.ReputationPerDaySinceCreation,
    AUM.ReputationQuartile,
    -- String expression for a summary text
    'Reputation: ' || AUM.Reputation || ', Posts: ' || AUM.TotalPosts || ', AvgScore: ' || ROUND(AUM.AvgPostScore, 2) || ', Rank: ' || AUM.OverallUserRank AS UserSummaryText
FROM AdvancedUserMetrics AS AUM
WHERE AUM.OverallUserRank <= 50 AND AUM.TotalQuestions >= 5 AND AUM.AvgPostScore > 5
    -- Complicated predicate combining multiple conditions with OR and AND
    AND (AUM.ReputationPerPost > 100 OR AUM.TotalBadges >= 10 OR AUM.ReputationPerDaySinceCreation > 5)
    AND AUM.ReputationQuartile = 1
    -- NULL logic: Ensures comparison only if previous rank exists, and checks for positive growth
    AND (AUM.PreviousReputationInRank = 0 OR AUM.Reputation > AUM.PreviousReputationInRank * 0.8)
ORDER BY AUM.Reputation DESC, AUM.TotalPosts DESC
LIMIT 100

UNION ALL

-- Perspective 2: High-Risk Question Creators based on closure rates and specific tag involvement
SELECT
    'High-Risk Question Creator' AS AnalysisCategory,
    AUM.UserId,
    AUM.UserIdentifierString,
    AUM.Reputation,
    AUM.TotalPosts,
    AUM.AvgPostScore,
    AUM.AvgViewsPerQuestion,
    AUM.TotalBadges,
    AUM.OverallUserRank,
    AUM.ReputationPerPost,
    AUM.PostScorePerCommentRatio,
    AUM.ClosedQuestionPercentage AS ClosedQuestionPercentage,
    AUM.DuplicatedPostCountForTopPost AS DuplicatedPostCount,
    AUM.ReputationPerDaySinceCreation,
    AUM.ReputationQuartile,
    'Reputation: ' || AUM.Reputation || ', Closed %: ' || AUM.ClosedQuestionPercentage || '%, Tags: ' || AUM.PostsWithSpecificTags || ', Duplicates: ' || COALESCE(AUM.DuplicatedPostCountForTopPost::TEXT, 'N/A') AS UserSummaryText
FROM AdvancedUserMetrics AS AUM
WHERE AUM.ClosedQuestionPercentage >= 20 AND AUM.TotalQuestions >= 10
    AND AUM.PostsWithSpecificTags >= 3 -- Focus on users with significant activity in specific technical domains
    AND AUM.DuplicatedPostCountForTopPost IS NOT NULL AND AUM.DuplicatedPostCountForTopPost > 0
    -- Correlated Subquery in WHERE: Compares a user's reputation growth to the overall average
    AND AUM.ReputationPerDaySinceCreation < (SELECT AVG(ReputationPerDaySinceCreation) FROM AdvancedUserMetrics WHERE ReputationPerDaySinceCreation IS NOT NULL)
    AND AUM.UserOverallScorePercentile < 50 -- Identifies users whose posts are generally below average quality
ORDER BY AUM.ClosedQuestionPercentage DESC, AUM.Reputation ASC
LIMIT 100;
