-- {"query": "1722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3002} 

WITH UserEngagementSummary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT C.Id) AS TotalComments,
        COALESCE(SUM(P.Score), 0) AS TotalPostScoreAggregate,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS PostUpvotesReceived,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS PostDownvotesReceived,
        (SELECT MIN(PH.CreationDate) FROM PostHistory PH WHERE PH.UserId = U.Id AND PH.PostHistoryTypeId IN (1,2,3)) AS FirstPostDate, -- Correlated subquery for first post creation
        SUM(CASE WHEN PH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostsClosedByVote,
        SUM(CASE WHEN PH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS PostsReopenedByVote
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN PostHistory PH ON U.Id = PH.UserId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (2,3) -- Up/Down votes on posts
    WHERE U.Reputation >= 50 AND U.LastAccessDate > '2021-06-01'
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate
),
PostDetailsExtended AS (
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.CreationDate AS PostCreationDate,
        P.Score,
        P.ViewCount,
        P.OwnerUserId,
        P.Title,
        P.Tags,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.LastEditDate,
        (SELECT COUNT(*) FROM Comments WHERE PostId = P.Id AND CreationDate > P.CreationDate) AS PostCommentCountAfterCreation, -- Correlated subquery for comments
        COALESCE(P.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(P.FavoriteCount, 0) AS ActualFavoriteCount,
        (P.Score * 0.5 + COALESCE(P.ViewCount, 0) * 0.1 + COALESCE(P.AnswerCount, 0) * 2 + COALESCE(P.FavoriteCount, 0) * 3) AS PostPopularityScore, -- Complicated calculation
        CASE
            WHEN P.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN P.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN P.AnswerCount > 0 THEN 'HasAnswers'
            ELSE 'Open'
        END AS PostStatus,
        LAG(P.CreationDate, 1, P.CreationDate) OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate) AS PrevPostCreationDate, -- Window function
        ROW_NUMBER() OVER (PARTITION BY P.OwnerUserId ORDER BY P.CreationDate DESC) AS UserPostSeqNum
    FROM Posts P
    WHERE P.PostTypeId IN (1, 2) -- Questions and Answers
      AND P.CreationDate >= '2020-01-01'
      AND P.Body IS NOT NULL
      AND LENGTH(P.Body) > 100 -- Filter out very short posts
      AND (P.Body LIKE '%sql%' OR P.Body LIKE '%database%' OR P.Tags LIKE '%<sql>%' OR P.Tags LIKE '%<database>%') -- String expressions
),
UserOverallMetrics AS (
    SELECT
        UES.UserId,
        UES.DisplayName,
        UES.Reputation,
        UES.UserCreationDate,
        UES.LastAccessDate,
        UES.TotalPosts,
        UES.TotalQuestions,
        UES.TotalAnswers,
        UES.TotalComments,
        UES.TotalPostScoreAggregate,
        UES.PostUpvotesReceived,
        UES.PostDownvotesReceived,
        UES.FirstPostDate,
        UES.PostsClosedByVote,
        UES.PostsReopenedByVote,
        COALESCE(B.GoldBadges, 0) AS GoldBadges,
        COALESCE(B.SilverBadges, 0) AS SilverBadges,
        COALESCE(B.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(PL.TotalLinkedPosts, 0) AS TotalLinkedPosts,
        COALESCE(PL.TotalDuplicatePostsLinked, 0) AS TotalDuplicatePostsLinked,
        ( -- Correlated subquery with string parsing for tags
            SELECT COUNT(DISTINCT TagNameArray.tag)
            FROM Posts P_inner
            CROSS JOIN LATERAL UNNEST(string_to_array(substring(P_inner.Tags, 2, length(P_inner.Tags)-2), '><')) AS TagNameArray(tag)
            WHERE P_inner.OwnerUserId = UES.UserId
              AND TagNameArray.tag ILIKE '%sql%'
        ) AS UserSqlTagsCount
    FROM UserEngagementSummary UES
    LEFT JOIN ( -- Subquery for badge aggregation
        SELECT
            B.UserId,
            SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges B
        GROUP BY B.UserId
    ) B ON UES.UserId = B.UserId
    LEFT JOIN ( -- Subquery for post link aggregation
        SELECT
            P.OwnerUserId AS UserId,
            COUNT(DISTINCT PL.RelatedPostId) AS TotalLinkedPosts,
            SUM(CASE WHEN PL.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicatePostsLinked
        FROM Posts P
        JOIN PostLinks PL ON P.Id = PL.PostId
        GROUP BY P.OwnerUserId
    ) PL ON UES.UserId = PL.UserId
),
RankedUsersAndPosts AS (
    SELECT
        UOM.UserId,
        UOM.DisplayName,
        UOM.Reputation,
        UOM.UserCreationDate,
        UOM.LastAccessDate,
        UOM.TotalPosts,
        UOM.TotalQuestions,
        UOM.TotalAnswers,
        UOM.TotalComments,
        UOM.TotalPostScoreAggregate,
        UOM.PostUpvotesReceived,
        UOM.PostDownvotesReceived,
        UOM.GoldBadges,
        UOM.SilverBadges,
        UOM.BronzeBadges,
        UOM.TotalLinkedPosts,
        UOM.TotalDuplicatePostsLinked,
        UOM.UserSqlTagsCount,
        PDE.PostId,
        PDE.Title AS PostTitle,
        PDE.PostCreationDate,
        PDE.PostPopularityScore,
        PDE.PostStatus,
        PDE.Score AS PostScore,
        PDE.ViewCount AS PostViewCount,
        PDE.ActualAnswerCount,
        PDE.ActualFavoriteCount,
        PDE.PostCommentCountAfterCreation,
        (EXTRACT(EPOCH FROM (UOM.LastAccessDate - UOM.UserCreationDate)) / 86400) AS DaysActiveSinceCreation, -- Date calculation
        (UOM.PostUpvotesReceived - UOM.PostDownvotesReceived) AS NetPostVotes,
        (CAST(UOM.TotalPosts AS DECIMAL) / NULLIF(EXTRACT(EPOCH FROM (UOM.LastAccessDate - UOM.UserCreationDate)) / 86400, 0)) AS PostsPerDayActive, -- Calculation with NULL logic
        RANK() OVER (ORDER BY UOM.Reputation DESC, UOM.TotalPosts DESC, UOM.GoldBadges DESC) AS UserGlobalRank, -- Window function
        DENSE_RANK() OVER (PARTITION BY UOM.UserId ORDER BY PDE.PostPopularityScore DESC) AS PostPopularityRankForUser, -- Window function
        NTILE(5) OVER (ORDER BY UOM.Reputation DESC) AS ReputationQuintile, -- Window function
        SUM(PDE.PostPopularityScore) OVER (PARTITION BY UOM.UserId) AS UserTotalPostPopularityScore, -- Window function
        AVG(PDE.Score) OVER (PARTITION BY UOM.UserId) AS UserAvgPostScore, -- Window function
        COUNT(CASE WHEN PDE.PostStatus = 'Closed' THEN 1 ELSE NULL END) OVER (PARTITION BY UOM.UserId) AS UserClosedPostCount -- Window function
    FROM UserOverallMetrics UOM
    JOIN PostDetailsExtended PDE ON UOM.UserId = PDE.OwnerUserId
    WHERE PDE.PostPopularityScore > 10 OR UOM.GoldBadges > 0 -- Complex predicate
),
SegmentedResults AS (
    -- Segment 1: High-reputation users with significant 'sql' related activity
    SELECT
        'HighRep_SQL_Pro' AS Segment,
        R.UserId,
        R.DisplayName,
        R.Reputation,
        R.UserGlobalRank,
        R.PostTitle,
        R.PostPopularityScore,
        R.PostPopularityRankForUser,
        R.DaysActiveSinceCreation,
        R.PostsPerDayActive,
        R.NetPostVotes,
        R.UserSqlTagsCount,
        'N/A' AS CorrelatedPostAnalysis_Detail -- Placeholder, specific correlated subquery in next segment
    FROM RankedUsersAndPosts R
    WHERE R.Reputation >= 10000
      AND R.UserSqlTagsCount > 0
      AND R.UserGlobalRank <= 1000
      AND R.ReputationQuintile = 1
      AND R.PostPopularityScore > 50
    UNION ALL -- Set operator
    -- Segment 2: Active contributors with many answers and good post quality, but not necessarily top-tier reputation
    SELECT
        'Active_Answerer' AS Segment,
        R.UserId,
        R.DisplayName,
        R.Reputation,
        R.UserGlobalRank,
        R.PostTitle,
        R.PostPopularityScore,
        R.PostPopularityRankForUser,
        R.DaysActiveSinceCreation,
        R.PostsPerDayActive,
        R.NetPostVotes,
        R.UserSqlTagsCount,
        ( -- Correlated subquery with string concatenation
            SELECT CONCAT('UserHasOtherPostsWithHigherScore:',
                          COUNT(P2.Id))
            FROM Posts P2
            WHERE P2.OwnerUserId = R.UserId
              AND P2.Id != R.PostId
              AND P2.Score > R.PostScore
              AND P2.CreationDate < R.PostCreationDate
        ) AS CorrelatedPostAnalysis_Detail
    FROM RankedUsersAndPosts R
    WHERE R.TotalAnswers >= 50
      AND R.UserAvgPostScore >= 5
      AND R.GoldBadges + R.SilverBadges >= 3
      AND R.PostsPerDayActive IS NOT NULL AND R.PostsPerDayActive > 0.1 -- NULL logic
      AND R.PostPopularityScore > 20
)
SELECT
    S.Segment,
    S.UserId,
    S.DisplayName,
    S.Reputation,
    S.UserGlobalRank,
    S.PostTitle,
    S.PostPopularityScore,
    S.PostPopularityRankForUser,
    S.DaysActiveSinceCreation,
    S.PostsPerDayActive,
    S.NetPostVotes,
    S.UserSqlTagsCount,
    S.CorrelatedPostAnalysis_Detail,
    CASE -- Complicated conditional expression
        WHEN S.Reputation > 50000 AND S.GoldBadges > 5 THEN 'Elite'
        WHEN S.Reputation > 10000 AND S.GoldBadges > 0 THEN 'Veteran'
        WHEN S.Reputation > 1000 THEN 'Experienced'
        ELSE 'Contributor'
    END AS UserCategory,
    'QueryGeneratedOn:' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS') AS QueryExecutionTimestampLabel -- String expression
FROM SegmentedResults S
ORDER BY
    S.Segment, S.Reputation DESC, S.PostPopularityScore DESC
LIMIT 10000;
