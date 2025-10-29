-- {"query": "1689.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3983} 

WITH UserEngagementSummary AS (
    -- Summarizes core user activity: posts, comments, scores, and general interaction
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        SUM(CASE WHEN P.AcceptedAnswerId IS NOT NULL AND P.OwnerUserId = U.Id THEN 1 ELSE 0 END) AS SelfAcceptedAnswers,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.LastAccessDate)) AS LastKnownActivityDate,
        -- Calculate the average daily upvotes given by the user, handling potential division by zero
        COALESCE(
            CAST(U.UpVotes AS NUMERIC) / NULLIF(EXTRACT(EPOCH FROM (U.LastAccessDate - U.CreationDate)) / (3600 * 24), 0),
            0
        ) AS AvgDailyUpvotesGiven
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostHistoricalMetrics AS (
    -- Gathers detailed metrics for posts including historical edits and vote counts from the Votes table
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostCurrentScore,
        P.ViewCount,
        P.AnswerCount,
        P.CommentCount,
        P.FavoriteCount,
        P.Title,
        P.Tags,
        P.ClosedDate,
        COUNT(DISTINCT PH_edit.Id) AS TotalEdits,
        COUNT(DISTINCT PH_close.Id) AS TotalCloseEvents,
        -- Correlated subquery to calculate net votes (upvotes - downvotes) from the Votes table
        (
            SELECT SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 WHEN V.VoteTypeId = 3 THEN -1 ELSE 0 END)
            FROM Votes V
            WHERE V.PostId = P.Id AND V.VoteTypeId IN (2, 3)
        ) AS NetVoteFromVotesTable,
        MAX(CASE WHEN PH_dup.PostHistoryTypeId = 10 AND PH_dup.Comment = '101' THEN TRUE ELSE FALSE END) AS IsClosedAsDuplicate,
        COALESCE(NULLIF(P.AnswerCount, 0) * 1.0 / NULLIF(P.ViewCount, 0), 0) AS AnswerToViewRatio,
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostSeqDesc -- Rank posts by creation date for each user
    FROM Posts P
    LEFT JOIN PostHistory PH_edit ON P.Id = PH_edit.PostId AND PH_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    LEFT JOIN PostHistory PH_close ON P.Id = PH_close.PostId AND PH_close.PostHistoryTypeId = 10 -- Post Closed event
    LEFT JOIN PostHistory PH_dup ON P.Id = PH_dup.PostId AND PH_dup.PostHistoryTypeId = 10 AND PH_dup.Comment = '101'
    GROUP BY
        P.Id, P.PostTypeId, P.OwnerUserId, P.CreationDate, P.Score, P.ViewCount, P.AnswerCount,
        P.CommentCount, P.FavoriteCount, P.Title, P.Tags, P.ClosedDate
),
BadgeAndLinkInfo AS (
    -- Aggregates badge counts and post link metrics for each user
    SELECT
        U.Id AS UserId,
        COUNT(B.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT PL_linked.RelatedPostId) FILTER (WHERE PL_linked.LinkTypeId = 1) AS TotalLinkedPostsByRelatedId,
        COUNT(DISTINCT PL_dup_source.RelatedPostId) FILTER (WHERE PL_dup_source.LinkTypeId = 3) AS TotalPostsAsDuplicateSource,
        COUNT(DISTINCT PL_dup_target.PostId) FILTER (WHERE PL_dup_target.LinkTypeId = 3) AS TotalPostsAreDuplicateTarget
    FROM Users U
    LEFT JOIN Badges B ON U.Id = B.UserId
    -- Join to PostLinks via subquery to filter links relevant to user's posts
    LEFT JOIN PostLinks PL_linked ON EXISTS (SELECT 1 FROM Posts WHERE Id = PL_linked.PostId AND OwnerUserId = U.Id)
    LEFT JOIN PostLinks PL_dup_source ON EXISTS (SELECT 1 FROM Posts WHERE Id = PL_dup_source.PostId AND OwnerUserId = U.Id)
    LEFT JOIN PostLinks PL_dup_target ON EXISTS (SELECT 1 FROM Posts WHERE Id = PL_dup_target.RelatedPostId AND OwnerUserId = U.Id)
    GROUP BY U.Id
),
UserOverallMetrics AS (
    -- Combines all user-centric metrics into a single view, adding window functions and tenure calculation
    SELECT
        UES.UserId,
        UES.DisplayName,
        UES.Reputation,
        UES.UserCreationDate,
        UES.LastKnownActivityDate,
        UES.TotalPosts,
        UES.QuestionsAsked,
        UES.AnswersProvided,
        UES.TotalComments,
        UES.TotalPostScore,
        UES.TotalCommentScore,
        UES.SelfAcceptedAnswers,
        UES.AvgDailyUpvotesGiven,
        BAI.TotalBadgesEarned,
        BAI.GoldBadges,
        BAI.SilverBadges,
        BAI.BronzeBadges,
        BAI.TotalLinkedPostsByRelatedId,
        BAI.TotalPostsAsDuplicateSource,
        BAI.TotalPostsAreDuplicateTarget,
        SUM(COALESCE(PHM.TotalEdits, 0)) AS AggregatePostEdits,
        SUM(COALESCE(PHM.TotalCloseEvents, 0)) AS AggregatePostCloseEvents,
        SUM(COALESCE(PHM.NetVoteFromVotesTable, 0)) AS AggregateNetVotes,
        AVG(COALESCE(PHM.AnswerToViewRatio, 0)) AS AvgAnswerToViewRatio,
        DENSE_RANK() OVER (ORDER BY UES.Reputation DESC, UES.TotalPostScore DESC) AS ReputationRank,
        NTILE(100) OVER (ORDER BY UES.TotalPosts DESC) AS TopPostersCentile,
        LAG(UES.LastKnownActivityDate, 1, UES.UserCreationDate) OVER (ORDER BY UES.LastKnownActivityDate) AS PrevUserActivityDate,
        EXTRACT(EPOCH FROM (UES.LastKnownActivityDate - UES.UserCreationDate)) / (3600.0 * 24 * 365.25) AS YearsActive -- User's active tenure in years
    FROM UserEngagementSummary UES
    LEFT JOIN PostHistoricalMetrics PHM ON UES.UserId = PHM.OwnerUserId
    LEFT JOIN BadgeAndLinkInfo BAI ON UES.UserId = BAI.UserId
    GROUP BY
        UES.UserId, UES.DisplayName, UES.Reputation, UES.UserCreationDate, UES.LastKnownActivityDate,
        UES.TotalPosts, UES.QuestionsAsked, UES.AnswersProvided, UES.TotalComments, UES.TotalPostScore,
        UES.TotalCommentScore, UES.SelfAcceptedAnswers, UES.AvgDailyUpvotesGiven,
        BAI.TotalBadgesEarned, BAI.GoldBadges, BAI.SilverBadges, BAI.BronzeBadges,
        BAI.TotalLinkedPostsByRelatedId, BAI.TotalPostsAsDuplicateSource, BAI.TotalPostsAreDuplicateTarget
),
GlobalBenchmarks AS (
    -- Calculates global averages for comparison metrics across all users
    SELECT
        AVG(Reputation) AS AvgReputation,
        AVG(TotalPosts) AS AvgTotalPosts,
        AVG(TotalComments) AS AvgTotalComments,
        AVG(TotalPostScore) AS AvgTotalPostScore,
        AVG(AggregateNetVotes) AS AvgAggregateNetVotes,
        AVG(TotalBadgesEarned) AS AvgTotalBadgesEarned,
        AVG(YearsActive) AS AvgYearsActive,
        AVG(AggregatePostEdits) AS AvgAggregatePostEdits
    FROM UserOverallMetrics
),
TopContributors AS (
    -- Identifies top users based on a combination of reputation, gold badges, and answer count
    SELECT
        UOM.UserId,
        UOM.DisplayName,
        UOM.Reputation,
        UOM.LastKnownActivityDate,
        UOM.TotalPosts,
        UOM.QuestionsAsked,
        UOM.AnswersProvided,
        UOM.TotalPostScore,
        UOM.AggregateNetVotes,
        UOM.GoldBadges,
        UOM.ReputationRank,
        'Top Contributor' AS Category,
        -- Aggregate common tags from their posts, splitting the string
        ARRAY_AGG(DISTINCT TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))) FILTER (WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2) AS CommonTags
    FROM UserOverallMetrics UOM
    JOIN Posts P ON UOM.UserId = P.OwnerUserId
    WHERE UOM.ReputationRank <= 100
      AND UOM.TotalPosts > 10
      AND UOM.AnswersProvided > UOM.QuestionsAsked
      AND UOM.GoldBadges > 0
    GROUP BY
        UOM.UserId, UOM.DisplayName, UOM.Reputation, UOM.LastKnownActivityDate, UOM.TotalPosts,
        UOM.QuestionsAsked, UOM.AnswersProvided, UOM.TotalPostScore, UOM.AggregateNetVotes,
        UOM.GoldBadges, UOM.ReputationRank
),
HighlyEngagedUsers AS (
    -- Identifies highly engaged users based on recent activity, comments, and edits relative to global averages
    SELECT
        UOM.UserId,
        UOM.DisplayName,
        UOM.Reputation,
        UOM.LastKnownActivityDate,
        UOM.TotalPosts,
        UOM.QuestionsAsked,
        UOM.AnswersProvided,
        UOM.TotalPostScore,
        UOM.AggregateNetVotes,
        UOM.GoldBadges,
        UOM.ReputationRank,
        'Highly Engaged' AS Category,
        ARRAY_AGG(DISTINCT TRIM(unnest(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><')))) FILTER (WHERE P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2) AS CommonTags
    FROM UserOverallMetrics UOM
    CROSS JOIN GlobalBenchmarks GB -- Using CROSS JOIN to access global averages easily in WHERE clause
    JOIN Posts P ON UOM.UserId = P.OwnerUserId
    WHERE UOM.LastKnownActivityDate >= (CURRENT_DATE - INTERVAL '6 months')
      AND UOM.TotalComments > GB.AvgTotalComments * 1.5
      AND UOM.AggregatePostEdits > GB.AvgAggregatePostEdits * 2
      AND UOM.ReputationRank <= 500
    GROUP BY
        UOM.UserId, UOM.DisplayName, UOM.Reputation, UOM.LastKnownActivityDate, UOM.TotalPosts,
        UOM.QuestionsAsked, UOM.AnswersProvided, UOM.TotalPostScore, UOM.AggregateNetVotes,
        UOM.GoldBadges, UOM.ReputationRank, GB.AvgTotalComments, GB.AvgAggregatePostEdits
),
CombinedEliteUsers AS (
    -- Combines the two elite user groups using UNION ALL
    SELECT * FROM TopContributors
    UNION ALL
    SELECT * FROM HighlyEngagedUsers
)
SELECT
    CEU.UserId,
    CEU.DisplayName,
    CEU.Reputation,
    CEU.Category,
    CEU.LastKnownActivityDate,
    CEU.TotalPosts,
    CEU.QuestionsAsked,
    CEU.AnswersProvided,
    CEU.TotalPostScore,
    CEU.AggregateNetVotes,
    CEU.GoldBadges,
    CEU.ReputationRank,
    GB.AvgReputation,
    GB.AvgTotalPosts,
    GB.AvgTotalComments,
    GB.AvgTotalPostScore,
    GB.AvgAggregateNetVotes,
    GB.AvgTotalBadgesEarned,
    -- Complex calculation: Engagement score per year active, weighting different contributions
    ROUND(
        (CEU.TotalPosts * 0.4 + CEU.AggregateNetVotes * 0.3 + CEU.GoldBadges * 10 + CEU.TotalPostScore * 0.2 + CEU.AnswersProvided * 0.5)
        / NULLIF(UOM.YearsActive, 0.001), 2
    ) AS EngagementPerYear,
    -- String expression: Summarize post types in a formatted string
    CONCAT_WS(' | ',
        'Q:' || CEU.QuestionsAsked,
        'A:' || CEU.AnswersProvided,
        'T:' || CEU.TotalPosts
    ) AS PostTypeSummary,
    -- Correlated subquery to fetch the text of the user's most recent active comment, handling potential NULLs
    COALESCE((
        SELECT C.Text
        FROM Comments C
        WHERE C.UserId = CEU.UserId AND C.CreationDate = (SELECT MAX(C2.CreationDate) FROM Comments C2 WHERE C2.UserId = CEU.UserId)
        LIMIT 1
    ), 'No recent comments') AS LastCommentText,
    -- NULL logic: Display a specific message if no Gold Badges are present
    COALESCE(CAST(CEU.GoldBadges AS VARCHAR), 'No Gold Badges Earned') AS GoldBadgeStatus,
    -- Check for the existence of questions with the 'sql' tag using an EXISTS subquery
    EXISTS (
        SELECT 1
        FROM PostHistoricalMetrics PHM_inner
        WHERE PHM_inner.OwnerUserId = CEU.UserId
          AND PHM_inner.PostTypeId = 1 -- Only questions
          AND PHM_inner.Tags ILIKE '%<sql>%'
    ) AS HasSQLQuestions,
    -- Demonstrate a RIGHT JOIN: retrieve all VoteTypes and associate them with elite users if they exist
    VT.Name AS VoteTypeName,
    -- Window function: count how many times an elite user used a specific vote type
    COUNT(V.Id) OVER (PARTITION BY CEU.UserId, VT.Name) AS VotesOfThisTypeByUser,
    CEU.CommonTags
FROM CombinedEliteUsers CEU
CROSS JOIN GlobalBenchmarks GB
LEFT JOIN UserOverallMetrics UOM ON CEU.UserId = UOM.UserId -- To get YearsActive for EngagementPerYear calculation
RIGHT JOIN Votes V ON CEU.UserId = V.UserId -- Intentionally using RIGHT JOIN to ensure all votes are considered, linking to elite users where possible
RIGHT JOIN VoteTypes VT ON V.VoteTypeId = VT.Id -- Links votes to their type names
WHERE
    CEU.Reputation IS NOT NULL -- Filters out rows from RIGHT JOIN where V.UserId had no match in CEU (i.e., non-elite users' votes)
    AND VT.Name IS NOT NULL -- Ensures only valid vote types are included
GROUP BY
    CEU.UserId, CEU.DisplayName, CEU.Reputation, CEU.Category, CEU.LastKnownActivityDate,
    CEU.TotalPosts, CEU.QuestionsAsked, CEU.AnswersProvided, CEU.TotalPostScore,
    CEU.AggregateNetVotes, CEU.GoldBadges, CEU.ReputationRank, GB.AvgReputation,
    GB.AvgTotalPosts, GB.AvgTotalComments, GB.AvgTotalPostScore, GB.AvgAggregateNetVotes,
    GB.AvgTotalBadgesEarned, UOM.YearsActive, CEU.CommonTags, VT.Name
HAVING
    COUNT(V.Id) OVER (PARTITION BY CEU.UserId, VT.Name) > 1 -- Only show vote types where an elite user has more than one vote
ORDER BY
    CEU.Reputation DESC, EngagementPerYear DESC, CEU.LastKnownActivityDate DESC
LIMIT 500;
