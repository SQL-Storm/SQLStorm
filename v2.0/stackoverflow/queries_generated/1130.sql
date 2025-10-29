-- {"query": "1130.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3523} 

WITH UserActivitySummary AS (
    -- Aggregates basic user activity metrics like post counts, comment counts, and derived stats.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate,
        U.LastAccessDate,
        U.Views AS UserViews,
        U.UpVotes AS UserUpVotesGiven,
        U.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 1 THEN P.Id END) AS TotalQuestionsPosted,
        COUNT(DISTINCT CASE WHEN P.PostTypeId = 2 THEN P.Id END) AS TotalAnswersPosted,
        COUNT(DISTINCT C.Id) AS TotalCommentsPosted,
        SUM(CASE WHEN P.ParentId IS NOT NULL AND P.Id = QuestionPosts.AcceptedAnswerId THEN 1 ELSE 0 END) AS TotalAcceptedAnswers,
        EXTRACT(EPOCH FROM (NOW() - U.LastAccessDate)) / 86400 AS TimeSinceLastAccessDays, -- Days since last access, using date arithmetic
        CASE
            WHEN (NOW() - U.CreationDate) IS NULL OR EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) = 0
            THEN 0.0 -- Handle division by zero for newly created users
            ELSE U.Reputation * 1.0 / (EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 86400.0)
        END AS ReputationPerDay,
        COALESCE(SUM(P.Score) * 1.0 / NULLIF(COUNT(P.Id), 0), 0.0) AS AveragePostScoreReceived, -- NULL logic, type casting
        (
            -- Correlated subquery to find the most frequent post type for each user
            SELECT PT.Name
            FROM Posts UserPosts
            JOIN PostTypes PT ON UserPosts.PostTypeId = PT.Id
            WHERE UserPosts.OwnerUserId = U.Id
            GROUP BY PT.Name, UserPosts.PostTypeId
            ORDER BY COUNT(UserPosts.Id) DESC, UserPosts.PostTypeId DESC
            LIMIT 1
        ) AS MostFrequentPostType
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    LEFT JOIN Posts QuestionPosts ON P.ParentId = QuestionPosts.Id -- To check if P (an answer) is an accepted answer for QuestionPosts
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Views, U.UpVotes, U.DownVotes
    HAVING U.Reputation > 100 -- Initial filter for more established users
),
PostQualityMetrics AS (
    -- Calculates post-specific metrics, including edit history, close events, and duplicate links for questions.
    SELECT
        PQ.Id AS PostId,
        PQ.OwnerUserId,
        PQ.Score AS PostScore,
        PQ.ViewCount,
        PQ.AnswerCount,
        PQ.FavoriteCount,
        PQ.Title,
        PQ.Tags,
        COALESCE(COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId IN (4, 5, 6, 8, 9)), 0) AS TotalEditEvents, -- Edits/rollbacks for Title, Body, Tags
        COALESCE(COUNT(DISTINCT PH.Id) FILTER (WHERE PH.PostHistoryTypeId = 10), 0) AS CloseVoteEvents, -- Post closed history
        COALESCE(COUNT(DISTINCT PL.RelatedPostId) FILTER (WHERE PL.LinkTypeId = 3), 0) AS DuplicateLinkCount, -- Counts how many times this post is linked as a duplicate
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS PostUpVotes,
        COALESCE(SUM(CASE WHEN V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS PostDownVotes
    FROM Posts PQ
    LEFT JOIN PostHistory PH ON PQ.Id = PH.PostId
    LEFT JOIN PostLinks PL ON PQ.Id = PL.PostId -- Assuming PostId is the source of the link
    LEFT JOIN Votes V ON PQ.Id = V.PostId
    WHERE PQ.PostTypeId = 1 -- Focus only on questions
    GROUP BY PQ.Id, PQ.OwnerUserId, PQ.Score, PQ.ViewCount, PQ.AnswerCount, PQ.FavoriteCount, PQ.Title, PQ.Tags
),
UserBadgeRanks AS (
    -- Summarizes badge counts and ranks users based on badge prestige.
    SELECT
        B.UserId,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) DESC, SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) DESC, B.UserId ASC) AS BadgeRank,
        STRING_AGG(DISTINCT B.Name, ', ' ORDER BY B.Name) AS AllBadgesList -- String aggregation
    FROM Badges B
    GROUP BY B.UserId
),
DailyActivityMetrics AS (
    -- Aggregates daily post, comment, and vote activity for users over the last 3 months.
    SELECT
        P.OwnerUserId AS UserId,
        DATE_TRUNC('day', P.CreationDate) AS ActivityDay,
        COUNT(P.Id) AS PostsOnDay,
        COUNT(C.Id) AS CommentsOnDay,
        SUM(CASE WHEN V.VoteTypeId IN (2, 8) THEN 1 ELSE 0 END) AS UpVotesOnDay,
        SUM(CASE WHEN V.VoteTypeId IN (3, 10) THEN 1 ELSE 0 END) AS DownVotesOnDay
    FROM Posts P
    LEFT JOIN Comments C ON P.Id = C.PostId AND DATE_TRUNC('day', P.CreationDate) = DATE_TRUNC('day', C.CreationDate)
    LEFT JOIN Votes V ON P.Id = V.PostId AND DATE_TRUNC('day', P.CreationDate) = DATE_TRUNC('day', V.CreationDate)
    WHERE P.CreationDate >= NOW() - INTERVAL '3 months' -- Focus on recent activity
    GROUP BY P.OwnerUserId, DATE_TRUNC('day', P.CreationDate)
),
UserSegment_HighRepAndGoldBadges AS (
    -- Defines a segment of users with high reputation and gold badges.
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        'High Reputation & Gold Badges' AS SegmentType
    FROM UserActivitySummary UAS
    JOIN UserBadgeRanks UBR ON UAS.UserId = UBR.UserId
    WHERE UAS.Reputation > 50000 AND UBR.GoldBadges >= 5
),
UserSegment_ActiveRecentContributors AS (
    -- Defines a segment of users with significant recent posting and commenting activity.
    SELECT
        UAS.UserId,
        UAS.DisplayName,
        'Active Contributor (Recent Posts & Comments)' AS SegmentType
    FROM UserActivitySummary UAS
    JOIN (
        SELECT UserId, SUM(PostsOnDay) AS TotalRecentPosts, SUM(CommentsOnDay) AS TotalRecentComments
        FROM DailyActivityMetrics
        GROUP BY UserId
    ) AS DAM_Agg ON UAS.UserId = DAM_Agg.UserId
    WHERE DAM_Agg.TotalRecentPosts >= 20 AND DAM_Agg.TotalRecentComments >= 10
),
UserSegment_SelectedUsers AS (
    -- Combines multiple user segments using UNION ALL, demonstrating set operators.
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_HighRepAndGoldBadges
    UNION ALL
    SELECT UserId, DisplayName, SegmentType FROM UserSegment_ActiveRecentContributors
    UNION ALL
    -- Also include a random sample of other active users for broader analysis
    SELECT UserId, DisplayName, 'Random Active User Sample' AS SegmentType
    FROM UserActivitySummary
    WHERE UserId NOT IN (SELECT UserId FROM UserSegment_HighRepAndGoldBadges UNION SELECT UserId FROM UserSegment_ActiveRecentContributors)
    ORDER BY RANDOM()
    LIMIT 100
)
-- Main Query: Combines all CTEs, applies window functions, correlated subqueries, and complex logic.
SELECT
    UAS.UserId,
    UAS.DisplayName,
    UAS.Reputation,
    UAS.CreationDate,
    UAS.LastAccessDate,
    UAS.TimeSinceLastAccessDays,
    UAS.ReputationPerDay,
    UAS.TotalQuestionsPosted,
    UAS.TotalAnswersPosted,
    UAS.TotalCommentsPosted,
    UAS.TotalAcceptedAnswers,
    UAS.AveragePostScoreReceived,
    UAS.MostFrequentPostType,
    UBR.GoldBadges,
    UBR.SilverBadges,
    UBR.BronzeBadges,
    UBR.BadgeRank,
    UBR.AllBadgesList,
    -- Window functions for global and partitioned ranking/averaging
    ROW_NUMBER() OVER (ORDER BY UAS.Reputation DESC, UAS.LastAccessDate DESC) AS GlobalReputationRank,
    DENSE_RANK() OVER (ORDER BY UAS.TotalQuestionsPosted DESC, UAS.TotalAnswersPosted DESC) AS ContributionRank,
    AVG(UAS.AveragePostScoreReceived) OVER (PARTITION BY UAS.MostFrequentPostType) AS AvgPostScoreByMainPostType,
    -- Correlated subquery: Fetches the title of the user's latest post
    (
        SELECT P_Latest.Title
        FROM Posts P_Latest
        WHERE P_Latest.OwnerUserId = UAS.UserId
        ORDER BY P_Latest.CreationDate DESC
        LIMIT 1
    ) AS LatestPostTitle,
    -- Correlated subquery with NULL logic: Fetches the text of the user's latest comment
    COALESCE(
        (
            SELECT C_Latest.Text
            FROM Comments C_Latest
            WHERE C_Latest.UserId = UAS.UserId
            ORDER BY C_Latest.CreationDate DESC
            LIMIT 1
        ),
        'No recent comments'
    ) AS LatestCommentText,
    -- Window functions for recent daily activity aggregates
    COALESCE(SUM(DAM.PostsOnDay) OVER (PARTITION BY UAS.UserId), 0) AS RecentTotalPosts,
    COALESCE(SUM(DAM.CommentsOnDay) OVER (PARTITION BY UAS.UserId), 0) AS RecentTotalComments,
    COALESCE(AVG(DAM.UpVotesOnDay) OVER (PARTITION BY UAS.UserId), 0.0) AS AvgDailyUpVotesRecent,
    COALESCE(AVG(DAM.DownVotesOnDay) OVER (PARTITION BY UAS.UserId), 0.0) AS AvgDailyDownVotesRecent,
    -- String manipulations and complex conditional aggregates from PostQualityMetrics
    STRING_AGG(DISTINCT PQM.Title || ' (Score: ' || PQM.PostScore || ' Edits: ' || PQM.TotalEditEvents || ')', '; ')
        FILTER (WHERE PQM.PostScore > 50 AND PQM.TotalEditEvents > 5 AND PQM.DuplicateLinkCount > 0 AND PQM.Title ILIKE '%sql%') AS HighlightedProblematicSQLQuestions,
    COALESCE(
        SUM(CASE
                WHEN PQM.TotalEditEvents > 5 AND PQM.CloseVoteEvents > 0 AND PQM.PostDownVotes > PQM.PostUpVotes THEN 1
                ELSE 0
            END),
        0
    ) AS HighlyEditedClosedAndDownvotedQuestionsCount,
    -- Correlated subquery with array functions for tag analysis
    (
        SELECT COUNT(DISTINCT tag)
        FROM (
            SELECT UNNEST(string_to_array(substring(P_Tag.Tags, 2, length(P_Tag.Tags)-2), '><')) AS tag
            FROM Posts P_Tag
            WHERE P_Tag.OwnerUserId = UAS.UserId AND P_Tag.PostTypeId = 1 AND P_Tag.Tags IS NOT NULL AND LENGTH(P_Tag.Tags) > 2
        ) AS UserTags
        WHERE tag IN (SELECT TagName FROM Tags WHERE IsModeratorOnly = TRUE)
    ) AS QuestionsWithModeratorTagsCount,
    -- NULL logic and complex expressions
    COALESCE(
        UAS.DisplayName,
        'Anonymous User ' || UAS.UserId::text -- Explicit type casting
    ) AS EffectiveDisplayName,
    NULLIF(UAS.UserViews, 0) AS UserViewsNonNull, -- NULLIF example
    COALESCE(SelectedUsers.SegmentType, 'Standard User') AS UserSegmentDescription,
    CASE WHEN UAS.Reputation > 10000 THEN 'HighRepContributor'
         WHEN UAS.Reputation BETWEEN 1000 AND 10000 THEN 'MidRepContributor'
         ELSE 'LowRepContributor'
    END AS ReputationTier,
    CASE WHEN UAS.TotalQuestionsPosted > 0 AND UAS.TotalAnswersPosted > 0 AND UAS.TotalCommentsPosted > 0 THEN 'DiverseContributor'
         WHEN UAS.TotalQuestionsPosted > 0 AND UAS.TotalAnswersPosted = 0 THEN 'Questioner'
         WHEN UAS.TotalAnswersPosted > 0 AND UAS.TotalQuestionsPosted = 0 THEN 'Answerer'
         ELSE 'Passive'
    END AS ContributionStyle
FROM UserActivitySummary UAS
LEFT JOIN UserBadgeRanks UBR ON UAS.UserId = UBR.UserId
LEFT JOIN PostQualityMetrics PQM ON UAS.UserId = PQM.OwnerUserId
LEFT JOIN DailyActivityMetrics DAM ON UAS.UserId = DAM.UserId
LEFT JOIN UserSegment_SelectedUsers SelectedUsers ON UAS.UserId = SelectedUsers.UserId
WHERE
    UAS.Reputation > (SELECT AVG(Reputation) FROM Users) -- Non-correlated subquery for filtering
    AND UAS.TotalQuestionsPosted >= 1
    AND UAS.AveragePostScoreReceived IS NOT NULL
    AND UAS.LastAccessDate > NOW() - INTERVAL '1 year' -- Active users in the last year
    AND UAS.UserId IN (SELECT UserId FROM UserSegment_SelectedUsers) -- Filter by our combined segments
GROUP BY -- Grouping ensures proper aggregation of joined PQM and DAM metrics per user
    UAS.UserId, UAS.DisplayName, UAS.Reputation, UAS.CreationDate, UAS.LastAccessDate, UAS.TimeSinceLastAccessDays,
    UAS.ReputationPerDay, UAS.TotalQuestionsPosted, UAS.TotalAnswersPosted, UAS.TotalCommentsPosted,
    UAS.TotalAcceptedAnswers, UAS.AveragePostScoreReceived, UAS.MostFrequentPostType,
    UBR.GoldBadges, UBR.SilverBadges, UBR.BronzeBadges, UBR.BadgeRank, UBR.AllBadgesList,
    UAS.UserViews, UAS.UserUpVotesGiven, UAS.UserDownVotesGiven, SelectedUsers.SegmentType
ORDER BY GlobalReputationRank ASC, HighlightedProblematicSQLQuestions DESC NULLS LAST
LIMIT 200; -- Limit results for practical benchmarking
