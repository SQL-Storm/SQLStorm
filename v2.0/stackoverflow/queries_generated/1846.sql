-- {"query": "1846.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3502} 

WITH UserEngagement AS (
    -- CTE 1: Aggregate user post and comment activity, and calculate some derived metrics.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.UpVotes AS TotalUpVotesGiven,
        U.DownVotes AS TotalDownVotesGiven,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswers,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        COUNT(DISTINCT C.Id) AS TotalComments,
        MAX(P.LastActivityDate) AS LastPostActivity,
        MAX(C.CreationDate) AS LastCommentActivity
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.UpVotes, U.DownVotes, U.CreationDate, U.LastAccessDate
),
BadgeSummary AS (
    -- CTE 2: Summarize badge counts for each user, identifying 'Gold' badge earners.
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(B.Date) AS FirstBadgeDate
    FROM Badges AS B
    GROUP BY B.UserId
),
PostHistoryDetails AS (
    -- CTE 3: Extract post history details, specifically focusing on closed questions and their reasons.
    SELECT
        PH.PostId,
        PH.UserId AS EditorUserId,
        PH.CreationDate AS HistoryDate,
        PH.PostHistoryTypeId,
        PHT.Name AS HistoryTypeName,
        CR.Name AS CloseReasonName,
        PH.Comment AS HistoryComment,
        -- Use NULLIF to avoid division by zero or empty strings in later calculations
        NULLIF(TRIM(PH.Text), '') AS HistoryTextRaw
    FROM PostHistory AS PH
    JOIN PostHistoryTypes AS PHT ON PH.PostHistoryTypeId = PHT.Id
    LEFT JOIN CloseReasonTypes AS CR ON PH.PostHistoryTypeId = 10 AND PH.Comment = CR.Id::varchar -- Assuming Comment stores CloseReasonId for type 10
),
PostTagAnalysis AS (
    -- CTE 4: Analyze tags for posts, focusing on specific "hot" tags (e.g., 'sql', 'performance') and their associated metrics.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        -- Extract tags into an array and filter for specific 'hot' tags
        ARRAY(SELECT TRIM(s) FROM UNNEST(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><')) AS s WHERE s IN ('sql', 'performance', 'database', 'optimization', 'indexing', 'query')) AS HotTags,
        -- Calculate tag density or complexity based on tag count
        CASE
            WHEN P.Tags IS NULL OR LENGTH(P.Tags) <= 2 THEN 0
            ELSE CARDINALITY(string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><'))
        END AS TagCount
    FROM Posts AS P
    WHERE P.PostTypeId = 1 -- Only questions have tags in this context
      AND P.Tags IS NOT NULL
      AND P.Tags != '><' -- Exclude empty tags
),
OverallCommunityMetrics AS (
    -- CTE 5: Calculate overall community averages for comparison (window function use)
    SELECT
        AVG(UE.Reputation) AS AvgReputation,
        AVG(UE.TotalPosts) AS AvgTotalPosts,
        AVG(UE.TotalPostScore) AS AvgTotalPostScore,
        AVG(UE.TotalComments) AS AvgTotalComments
    FROM UserEngagement AS UE
),
UserCloseReasonSummary AS (
    -- CTE 6: Summarize close reasons for posts owned by each user.
    SELECT
        P.OwnerUserId AS UserId,
        PHD.PostId,
        PHD.CloseReasonName
    FROM Posts AS P
    JOIN PostHistoryDetails AS PHD ON P.Id = PHD.PostId
    WHERE PHD.PostHistoryTypeId = 10 -- Post Closed
),
HighImpactUsers AS (
    -- Subquery 1: Identify "High-Impact" users based on a composite score combining reputation, badges, post/comment scores, and tag contributions.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalQuestions,
        UE.TotalAnswers,
        COALESCE(BS.GoldBadges, 0) AS GoldBadgesCount,
        UE.TotalPostScore,
        UE.TotalCommentScore,
        SUM(CASE WHEN PTA.HotTags IS NOT NULL AND CARDINALITY(PTA.HotTags) > 0 THEN 1 ELSE 0 END) AS PostsWithHotTags,
        CAST(UE.TotalUpVotesGiven AS DECIMAL) / NULLIF(UE.TotalDownVotesGiven + 1, 0) AS UpDownVoteRatio, -- Ratio of upvotes given to downvotes given
        UE.TotalPosts + UE.TotalComments AS TotalActivityEvents,
        -- Complex calculation for a "UserScore"
        (UE.Reputation * 0.5)
        + (COALESCE(BS.GoldBadges, 0) * 100)
        + (UE.TotalPostScore * 0.7)
        + (UE.TotalCommentScore * 0.3)
        + (COUNT(DISTINCT UCRS.PostId) FILTER (WHERE UCRS.CloseReasonName IN ('Duplicate', 'Off-topic', 'Needs details or clarity')) * -50) -- Penalize for closed questions
        + (SUM(CASE WHEN PTA.HotTags IS NOT NULL AND CARDINALITY(PTA.HotTags) > 0 THEN 1 ELSE 0 END) * 20) AS UserScore,
        -- Window function: Rank users by their UserScore
        RANK() OVER (ORDER BY (
            (UE.Reputation * 0.5)
            + (COALESCE(BS.GoldBadges, 0) * 100)
            + (UE.TotalPostScore * 0.7)
            + (UE.TotalCommentScore * 0.3)
            + (COUNT(DISTINCT UCRS.PostId) FILTER (WHERE UCRS.CloseReasonName IN ('Duplicate', 'Off-topic', 'Needs details or clarity')) * -50)
            + (SUM(CASE WHEN PTA.HotTags IS NOT NULL AND CARDINALITY(PTA.HotTags) > 0 THEN 1 ELSE 0 END) * 20)
        ) DESC) AS ImpactRank,
        -- Window function: Calculate the moving average of TotalPostScore for users with similar TotalPosts
        AVG(UE.TotalPostScore) OVER (PARTITION BY FLOOR(UE.TotalPosts / 10) * 10 ORDER BY UE.Reputation) AS AvgScoreInBand,
        -- Correlated Subquery: Check if user has ever made a comment containing a specific keyword (case-insensitive) in the last year
        (SELECT COUNT(DISTINCT C2.Id)
         FROM Comments AS C2
         WHERE C2.UserId = UE.UserId
           AND LOWER(C2.Text) LIKE '%performance bottleneck%'
           AND C2.CreationDate > UE.LastAccessDate - INTERVAL '1 year' -- only recent comments
        ) AS CorrelatedSubqueryMetric,
        OCM.AvgReputation AS CommunityAvgReputation,
        (UE.Reputation - OCM.AvgReputation) AS ReputationDeltaFromAvg,
        -- String expression: Truncate DisplayName if too long and append '...'
        CASE
            WHEN LENGTH(UE.DisplayName) > 20 THEN LEFT(UE.DisplayName, 17) || '...'
            ELSE UE.DisplayName
        END AS ShortDisplayName,
        -- NULL logic: Display 'N/A' if no last activity
        COALESCE(UE.LastPostActivity::varchar, UE.LastCommentActivity::varchar, 'N/A') AS LastActivityCombined,
        'High-Impact User' AS UserCategory
    FROM UserEngagement AS UE
    LEFT JOIN BadgeSummary AS BS ON UE.UserId = BS.UserId
    LEFT JOIN PostTagAnalysis AS PTA ON UE.UserId = PTA.OwnerUserId
    LEFT JOIN UserCloseReasonSummary AS UCRS ON UE.UserId = UCRS.UserId
    CROSS JOIN OverallCommunityMetrics AS OCM -- Cross join for community averages
    WHERE
        UE.Reputation > OCM.AvgReputation * 1.2 -- Users with significantly above average reputation
        AND COALESCE(BS.GoldBadges, 0) > 0 -- Must have at least one gold badge
        AND UE.TotalQuestions >= 5 -- At least 5 questions
        AND UE.TotalAnswers >= 10 -- At least 10 answers
        AND (
            -- Complicated predicate: Users with hot tags OR have commented on posts with hot tags
            EXISTS (SELECT 1 FROM PostTagAnalysis WHERE OwnerUserId = UE.UserId AND CARDINALITY(HotTags) > 0)
            OR EXISTS (SELECT 1 FROM Comments WHERE UserId = UE.UserId AND PostId IN (SELECT Id FROM Posts WHERE Tags LIKE '%<sql>%' OR Tags LIKE '%<performance>%'))
        )
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.TotalQuestions, UE.TotalAnswers,
        COALESCE(BS.GoldBadges, 0), UE.TotalPostScore, UE.TotalCommentScore,
        UE.TotalUpVotesGiven, UE.TotalDownVotesGiven, UE.TotalPosts, UE.TotalComments,
        UE.LastPostActivity, UE.LastCommentActivity, OCM.AvgReputation
    HAVING
        COUNT(DISTINCT UCRS.PostId) FILTER (WHERE UCRS.CloseReasonName IN ('Duplicate', 'Off-topic', 'Needs details or clarity')) < UE.TotalQuestions / 2 -- Less than half of their questions are closed for these reasons
),
CommentGurus AS (
    -- Subquery 2: Identify "Comment Gurus" based on high comment activity and score, often with fewer posts.
    SELECT
        UE.UserId,
        UE.DisplayName,
        UE.Reputation,
        UE.TotalQuestions,
        UE.TotalAnswers,
        COALESCE(BS.GoldBadges, 0) AS GoldBadgesCount,
        UE.TotalPostScore,
        UE.TotalCommentScore,
        SUM(CASE WHEN PTA.HotTags IS NOT NULL AND CARDINALITY(PTA.HotTags) > 0 THEN 1 ELSE 0 END) AS PostsWithHotTags,
        CAST(UE.TotalUpVotesGiven AS DECIMAL) / NULLIF(UE.TotalDownVotesGiven + 1, 0) AS UpDownVoteRatio,
        UE.TotalPosts + UE.TotalComments AS TotalActivityEvents,
        -- Different composite score for "Comment Gurus"
        (UE.Reputation * 0.2)
        + (COALESCE(BS.SilverBadges, 0) * 50) -- Silver badges contribute more here
        + (UE.TotalPostScore * 0.1)
        + (UE.TotalCommentScore * 1.0) -- Comment score is weighted heavily
        + (UE.TotalComments * 0.5) AS UserScore,
        RANK() OVER (ORDER BY (
            (UE.Reputation * 0.2)
            + (COALESCE(BS.SilverBadges, 0) * 50)
            + (UE.TotalPostScore * 0.1)
            + (UE.TotalCommentScore * 1.0)
            + (UE.TotalComments * 0.5)
        ) DESC) AS ImpactRank, -- Reusing alias for rank
        AVG(UE.TotalCommentScore) OVER (PARTITION BY FLOOR(UE.TotalComments / 50) * 50 ORDER BY UE.Reputation) AS AvgScoreInBand, -- Different window function
        -- Correlated Subquery: Check for recent comments about 'clarification'
        (SELECT COUNT(DISTINCT C2.Id)
         FROM Comments AS C2
         WHERE C2.UserId = UE.UserId
           AND LOWER(C2.Text) LIKE '%clarification%'
           AND C2.CreationDate > UE.LastAccessDate - INTERVAL '6 months'
        ) AS CorrelatedSubqueryMetric, -- Different correlated subquery
        OCM.AvgReputation AS CommunityAvgReputation,
        (UE.Reputation - OCM.AvgReputation) AS ReputationDeltaFromAvg,
        CASE
            WHEN LENGTH(UE.DisplayName) > 20 THEN LEFT(UE.DisplayName, 17) || '...'
            ELSE UE.DisplayName
        END AS ShortDisplayName,
        COALESCE(UE.LastCommentActivity::varchar, UE.LastPostActivity::varchar, 'N/A') AS LastActivityCombined,
        'Comment Guru' AS UserCategory
    FROM UserEngagement AS UE
    LEFT JOIN BadgeSummary AS BS ON UE.UserId = BS.UserId
    LEFT JOIN PostTagAnalysis AS PTA ON UE.UserId = PTA.OwnerUserId -- Still useful for context
    CROSS JOIN OverallCommunityMetrics AS OCM
    WHERE
        UE.TotalComments >= OCM.AvgTotalComments * 1.5 -- Significant comment activity
        AND UE.TotalCommentScore >= 100 -- Good overall comment score
        AND COALESCE(BS.GoldBadges, 0) = 0 -- Exclude users already caught by "High-Impact" to make categories distinct
        AND UE.TotalQuestions < 50 -- Lower post count to differentiate from "High-Impact"
        AND (
            UE.TotalAnswers < 50
            OR UE.TotalAnswers IS NULL
        )
    GROUP BY
        UE.UserId, UE.DisplayName, UE.Reputation, UE.TotalQuestions, UE.TotalAnswers,
        COALESCE(BS.GoldBadges, 0), COALESCE(BS.SilverBadges, 0), UE.TotalPostScore, UE.TotalCommentScore,
        UE.TotalUpVotesGiven, UE.TotalDownVotesGiven, UE.TotalPosts, UE.TotalComments,
        UE.LastPostActivity, UE.LastCommentActivity, OCM.AvgReputation
)
-- Final result: Combine results from both categories and order by composite score.
SELECT *
FROM HighImpactUsers
UNION ALL
SELECT *
FROM CommentGurus
ORDER BY UserScore DESC, Reputation DESC
LIMIT 100;
