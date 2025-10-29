-- {"query": "1936.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3422} 

WITH UserBaseStats AS (
    -- Gathers fundamental user metrics, including total posts, comments, and their aggregated scores.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        COALESCE(U.Location, 'Unknown') AS UserLocation,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPosts,
        COUNT(DISTINCT C.Id) AS TotalComments,
        SUM(COALESCE(P.Score, 0)) AS TotalPostScore,
        SUM(COALESCE(C.Score, 0)) AS TotalCommentScore,
        MAX(COALESCE(P.LastActivityDate, C.CreationDate, U.CreationDate)) AS LastUserActivity
    FROM Users U
    LEFT JOIN Posts P ON U.Id = P.OwnerUserId
    LEFT JOIN Comments C ON U.Id = C.UserId
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.Location, U.Views
),
PostTagDetails AS (
    -- Extracts tags from posts, calculates up/down vote counts, and identifies keyword presence in post bodies.
    SELECT
        P.Id AS PostId,
        P.PostTypeId,
        P.OwnerUserId,
        P.CreationDate AS PostCreationDate,
        P.Score AS PostScore,
        P.ViewCount,
        P.AnswerCount,
        P.FavoriteCount,
        P.ClosedDate,
        P.AcceptedAnswerId,
        P.ParentId,
        CASE
            WHEN P.PostTypeId = 2 AND Q.AcceptedAnswerId = P.Id THEN TRUE
            ELSE FALSE
        END AS IsAcceptedAnswer,
        UpVote.VoteCount AS UpVoteCount,
        DownVote.VoteCount AS DownVoteCount,
        TagArray.tags_array AS ParsedTags,
        -- Detects specific keywords related to 'performance' or 'optimization' in the post body.
        CASE WHEN P.Body ILIKE '%performance%' OR P.Body ILIKE '%optimization%' THEN 1 ELSE 0 END AS HasPerformanceKeyword,
        -- Detects specific keywords related to 'benchmark' or 'scaling' in the post body.
        CASE WHEN P.Body ILIKE '%benchmark%' OR P.Body ILIKE '%scaling%' THEN 1 ELSE 0 END AS HasBenchmarkScalingKeyword
    FROM Posts P
    LEFT JOIN Posts Q ON P.ParentId = Q.Id AND Q.PostTypeId = 1 -- Links answers to their parent questions to check for acceptance.
    LEFT JOIN LATERAL (SELECT COUNT(V.Id) AS VoteCount FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 2) AS UpVote ON TRUE
    LEFT JOIN LATERAL (SELECT COUNT(V.Id) AS VoteCount FROM Votes V WHERE V.PostId = P.Id AND V.VoteTypeId = 3) AS DownVote ON TRUE
    LEFT JOIN LATERAL (
        SELECT CASE WHEN P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 THEN string_to_array(SUBSTRING(P.Tags, 2, LENGTH(P.Tags) - 2), '><') ELSE ARRAY[]::varchar[] END AS tags_array
    ) AS TagArray ON TRUE
    WHERE P.OwnerUserId IS NOT NULL AND P.PostTypeId IN (1, 2) -- Focuses on Questions (1) and Answers (2).
),
UserPostAggregates AS (
    -- Aggregates detailed post-related statistics for each user, including keyword-specific post counts and unique tags used.
    SELECT
        PTD.OwnerUserId AS UserId,
        COUNT(PTD.PostId) AS UserTotalPosts,
        SUM(PTD.PostScore) AS UserTotalPostScore,
        SUM(COALESCE(PTD.ViewCount, 0)) AS UserTotalPostViews,
        SUM(CASE WHEN PTD.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestionCount,
        SUM(CASE WHEN PTD.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswerCount,
        SUM(CASE WHEN PTD.PostTypeId = 1 AND PTD.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) AS UserClosedQuestionCount,
        SUM(CASE WHEN PTD.IsAcceptedAnswer THEN 1 ELSE 0 END) AS UserAcceptedAnswerCount,
        SUM(PTD.UpVoteCount) AS UserTotalPostUpVotes,
        SUM(PTD.DownVoteCount) AS UserTotalPostDownVotes,
        AVG(PTD.PostScore) AS AvgPostScore,
        MAX(PTD.PostScore) AS MaxPostScore,
        MAX(PTD.ViewCount) AS MaxPostViewCount,
        AVG(CASE WHEN PTD.PostTypeId = 1 THEN COALESCE(PTD.AnswerCount, 0) ELSE NULL END) AS AvgAnswersPerQuestion,
        COUNT(DISTINCT UNNEST(PTD.ParsedTags)) AS UniqueTagsPosted, -- Counts unique tags by unnesting the array.
        SUM(PTD.HasPerformanceKeyword) AS PerformanceKeywordPosts,
        SUM(PTD.HasBenchmarkScalingKeyword) AS BenchmarkScalingKeywordPosts,
        DATE_PART('day', MAX(PTD.CreationDate) - MIN(PTD.CreationDate)) AS DaysActivePosting
    FROM PostTagDetails PTD
    GROUP BY PTD.OwnerUserId
),
UserBadgeSummary AS (
    -- Summarizes badge counts by class for each user and records their last badge award date.
    SELECT
        B.UserId,
        COUNT(CASE WHEN B.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN B.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN B.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(B.Date) AS LastBadgeAwardDate
    FROM Badges B
    GROUP BY B.UserId
),
UserEditHistory AS (
    -- Aggregates post edit history, distinguishing between content edits and significant body changes.
    SELECT
        PH.UserId,
        COUNT(PH.Id) AS TotalPostHistoryEntries,
        SUM(CASE WHEN PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title (4), Body (5), Tags (6) edits.
        SUM(CASE WHEN PH.UserId = P.OwnerUserId AND PH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS SelfEditCount,
        MAX(PH.CreationDate) AS LastEditDate,
        COUNT(DISTINCT PH.PostId) AS UniquePostsEdited,
        -- Identifies significant body edits (PostHistoryTypeId = 5) where text length significantly changed (more than 10 spaces difference).
        SUM(CASE
                WHEN PH.PostHistoryTypeId = 5 AND P.Body IS NOT NULL AND PH.Text IS NOT NULL
                AND ABS((LENGTH(P.Body) - LENGTH(REPLACE(P.Body, ' ', ''))) - (LENGTH(PH.Text) - LENGTH(REPLACE(PH.Text, ' ', '')))) > 10
                THEN 1
                ELSE 0
            END) AS SignificantBodyEdits
    FROM PostHistory PH
    JOIN Posts P ON PH.PostId = P.Id
    WHERE PH.UserId IS NOT NULL
    GROUP BY PH.UserId
),
UserOverallMetrics AS (
    -- Combines all user-centric CTEs and calculates an 'Influence Score' along with various ranking metrics using window functions.
    SELECT
        UBS.UserId,
        UBS.DisplayName,
        UBS.Reputation,
        UBS.UserCreationDate,
        UBS.LastAccessDate,
        UAS.UserTotalPosts,
        UAS.UserQuestionCount,
        UAS.UserAnswerCount,
        UAS.UserAcceptedAnswerCount,
        UAS.TotalPostScore,
        UHS.EditCount,
        UHS.SelfEditCount,
        UBS.TotalComments,
        UBS.TotalCommentScore,
        UBS.UserProfileViews,
        COALESCE(UBG.GoldBadges, 0) AS GoldBadges,
        COALESCE(UBG.SilverBadges, 0) AS SilverBadges,
        COALESCE(UBG.BronzeBadges, 0) AS BronzeBadges,
        UAS.PerformanceKeywordPosts,
        UAS.BenchmarkScalingKeywordPosts,
        -- Calculated 'RawInfluenceScore' based on a weighted sum of various user activities and achievements.
        (UBS.Reputation * 0.1) +
        (UAS.UserAcceptedAnswerCount * 5) +
        (UAS.TotalPostScore * 0.5) +
        (COALESCE(UBG.GoldBadges, 0) * 10) +
        (COALESCE(UBG.SilverBadges, 0) * 5) +
        (COALESCE(UHS.EditCount, 0) * 0.2) AS RawInfluenceScore,

        -- Window function: Ranks users by their reputation in descending order.
        RANK() OVER (ORDER BY UBS.Reputation DESC) AS ReputationRank,
        -- Window function: Divides users into 4 quartiles based on their total post score.
        NTILE(4) OVER (ORDER BY UAS.TotalPostScore DESC) AS PostScoreQuartile,
        -- Window function: Calculates the average accepted answers for users within similar reputation brackets (intervals of 1000).
        AVG(UAS.UserAcceptedAnswerCount) OVER (PARTITION BY FLOOR(UBS.Reputation / 1000) * 1000) AS AvgAcceptedAnswersInRepGroup,
        -- Correlated Subquery: Checks if the user owns any posts that are marked as 'duplicate source' in PostLinks.
        EXISTS (
            SELECT 1
            FROM PostLinks PL
            JOIN Posts P_link ON PL.PostId = P_link.Id
            WHERE P_link.OwnerUserId = UBS.UserId
            AND PL.LinkTypeId = 3 -- LinkType 3 = Duplicate.
        ) AS HasSourceDuplicatePosts,
        -- Correlated Subquery: Retrieves the text of the most recent comment on one of the user's highly-scored questions (score > 100).
        (
            SELECT C.Text
            FROM Comments C
            JOIN Posts P_comment ON C.PostId = P_comment.Id
            WHERE P_comment.OwnerUserId = UBS.UserId
            AND P_comment.PostTypeId = 1 AND P_comment.Score > 100
            ORDER BY C.CreationDate DESC
            LIMIT 1
        ) AS MostRecentCommentOnHighScoreQuestion,
        -- String expression: Concatenates display name and location into a single string, handling NULLs gracefully.
        COALESCE(UBS.DisplayName, 'N/A') || ' (' || COALESCE(UBS.UserLocation, 'Unknown') || ')' AS UserDisplayInfo,
        -- NULL logic: Calculates the number of days between the user's last activity and their last badge award, if both exist.
        CASE
            WHEN UBS.LastUserActivity IS NOT NULL AND UBG.LastBadgeAwardDate IS NOT NULL
            THEN DATE_PART('day', UBS.LastUserActivity - UBG.LastBadgeAwardDate)
            ELSE NULL
        END AS DaysSinceLastBadgeAward
    FROM UserBaseStats UBS
    LEFT JOIN UserPostAggregates UAS ON UBS.UserId = UAS.UserId
    LEFT JOIN UserBadgeSummary UBG ON UBS.UserId = UBG.UserId
    LEFT JOIN UserEditHistory UHS ON UBS.UserId = UHS.UserId
    WHERE
        UBS.Reputation >= 1000 -- Filters for users with at least 1000 reputation.
        AND COALESCE(UAS.UserTotalPosts, 0) > 10 -- Ensures users have a minimum of 10 posts.
        AND (COALESCE(UAS.UserAcceptedAnswerCount, 0) > 0 OR COALESCE(UAS.UserQuestionCount, 0) > 0) -- Must have at least one question or accepted answer.
)
-- Combines two distinct sets of 'high-impact' users using a UNION ALL operator for a comprehensive benchmark result.
SELECT
    UM.UserId,
    UM.DisplayName,
    UM.Reputation,
    UM.UserDisplayInfo,
    UM.UserTotalPosts,
    UM.UserQuestionCount,
    UM.UserAnswerCount,
    UM.UserAcceptedAnswerCount,
    UM.TotalPostScore,
    UM.EditCount,
    UM.GoldBadges,
    UM.SilverBadges,
    UM.RawInfluenceScore,
    UM.ReputationRank,
    UM.PostScoreQuartile,
    UM.AvgAcceptedAnswersInRepGroup,
    UM.HasSourceDuplicatePosts,
    UM.MostRecentCommentOnHighScoreQuestion,
    UM.DaysSinceLastBadgeAward,
    'HighReputationContributor' AS ImpactCategory
FROM UserOverallMetrics UM
WHERE
    UM.Reputation >= 5000 -- Defines users with very high reputation.
    AND UM.UserAcceptedAnswerCount >= 5 -- Requires at least 5 accepted answers.
    AND COALESCE(UM.EditCount, 0) >= 10 -- Requires at least 10 edits.
    AND UM.PerformanceKeywordPosts >= 1 -- Requires engagement in 'performance' related topics.

UNION ALL

SELECT
    UM.UserId,
    UM.DisplayName,
    UM.Reputation,
    UM.UserDisplayInfo,
    UM.UserTotalPosts,
    UM.UserQuestionCount,
    UM.UserAnswerCount,
    UM.UserAcceptedAnswerCount,
    UM.TotalPostScore,
    UM.EditCount,
    UM.GoldBadges,
    UM.SilverBadges,
    UM.RawInfluenceScore,
    UM.ReputationRank,
    UM.PostScoreQuartile,
    UM.AvgAcceptedAnswersInRepGroup,
    UM.HasSourceDuplicatePosts,
    UM.MostRecentCommentOnHighScoreQuestion,
    UM.DaysSinceLastBadgeAward,
    'TopQuestionerAnswerer' AS ImpactCategory
FROM UserOverallMetrics UM
WHERE
    UM.PostScoreQuartile = 1 -- Filters for users in the top 25% by total post score.
    AND UM.UserQuestionCount >= 5 -- Requires at least 5 questions asked.
    AND UM.UserAnswerCount >= 5 -- Requires at least 5 answers provided.
    AND UM.HasSourceDuplicatePosts IS FALSE -- Excludes users known for duplicate posts.
    AND UM.MostRecentCommentOnHighScoreQuestion IS NOT NULL -- Ensures engagement with their own highly-scored questions.

ORDER BY RawInfluenceScore DESC, Reputation DESC
LIMIT 1000;
