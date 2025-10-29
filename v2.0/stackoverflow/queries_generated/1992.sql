-- {"query": "1992.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 5907} 

WITH TopInteractedTags AS (
    -- Identify tags that are popular based on post count and involvement in post links (duplicates/linked)
    SELECT
        T.Id AS TagId,
        T.TagName,
        T.Count AS InitialTagPostCount,
        -- Aggregate count of posts related to this tag that are involved in a PostLink
        COALESCE(SUM(CASE WHEN PL.LinkTypeId IN (1, 3) AND (P_link.Id = PL.PostId OR P_link.Id = PL.RelatedPostId) THEN 1 ELSE 0 END), 0) AS LinkInteractionCount
    FROM Tags AS T
    -- Join Posts to link tags to actual posts, then PostLinks to find interactions
    LEFT JOIN Posts AS P_link ON P_link.Tags LIKE '%<' || T.TagName || '>%'
    LEFT JOIN PostLinks AS PL ON P_link.Id = PL.PostId OR P_link.Id = PL.RelatedPostId
    WHERE T.TagName IS NOT NULL AND T.TagName != ''
    GROUP BY T.Id, T.TagName, T.Count
    HAVING T.Count + COALESCE(SUM(CASE WHEN PL.LinkTypeId IN (1, 3) AND (P_link.Id = PL.PostId OR P_link.Id = PL.RelatedPostId) THEN 1 ELSE 0 END), 0) > 50
    ORDER BY (T.Count + COALESCE(SUM(CASE WHEN PL.LinkTypeId IN (1, 3) AND (P_link.Id = PL.PostId OR P_link.Id = PL.RelatedPostId) THEN 1 ELSE 0 END), 0)) DESC
    LIMIT 75 -- Consider top 75 interacting tags for our analysis
),
ActiveUserPostSummary AS (
    -- Summarize post-related activity for users owning posts in the TopInteractedTags
    SELECT
        P.OwnerUserId AS UserId,
        COUNT(DISTINCT P.Id) AS TotalPostsInScope,
        SUM(P.Score) AS TotalPostScoreInScope,
        SUM(P.ViewCount) AS TotalPostViewsInScope,
        COUNT(CASE WHEN P.PostTypeId = 1 THEN P.Id ELSE NULL END) AS QuestionCountInScope,
        COUNT(CASE WHEN P.PostTypeId = 2 THEN P.Id ELSE NULL END) AS AnswerCountInScope,
        SUM(P.AnswerCount) AS TotalAnswersOnQuestionsOwned, -- NULL for answers, only counts for questions
        AVG(CASE WHEN P.PostTypeId = 1 THEN P.FavoriteCount ELSE NULL END) AS AvgQuestionFavoriteCount,
        MAX(P.CreationDate) AS LastPostCreationDate,
        MIN(P.CreationDate) AS FirstPostCreationDate,
        CAST(COUNT(DISTINCT P.Id) AS NUMERIC) / (EXTRACT(EPOCH FROM (MAX(P.CreationDate) - MIN(P.CreationDate) + INTERVAL '1 day')) / (60 * 60 * 24 * 365.25)) AS PostDensityPerYear
    FROM Posts AS P
    INNER JOIN TopInteractedTags AS TIT ON P.Tags LIKE '%<' || TIT.TagName || '>%' -- Dynamic tag matching
    WHERE P.OwnerUserId IS NOT NULL
      AND P.PostTypeId IN (1, 2) -- Only questions and answers
      AND P.CreationDate BETWEEN '2016-01-01' AND '2023-12-31' -- Specific date range for activity
    GROUP BY P.OwnerUserId
    HAVING COUNT(DISTINCT P.Id) >= 10 AND SUM(P.Score) >= 50
),
PostEditChangeHistory AS (
    -- Detailed analysis of post history events focusing on edits and close/reopen actions
    SELECT
        PH.PostId,
        PH.UserId AS HistoryEventUserId,
        PH.CreationDate AS EventDate,
        PH.PostHistoryTypeId,
        PH.Comment AS HistoryComment,
        LENGTH(PH.Text) AS HistoryTextLength,
        -- Calculate time since last event for the same post
        LAG(PH.CreationDate, 1, PH.CreationDate) OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS PreviousEventDate,
        ROW_NUMBER() OVER (PARTITION BY PH.PostId ORDER BY PH.CreationDate) AS EventSequenceNum,
        COUNT(PH.Id) OVER (PARTITION BY PH.PostId, PH.PostHistoryTypeId) AS TypeSpecificPostEvents
    FROM PostHistory AS PH
    INNER JOIN Posts AS P ON PH.PostId = P.Id
    INNER JOIN ActiveUserPostSummary AS AUPS ON P.OwnerUserId = AUPS.UserId -- Only analyze posts from active users
    WHERE PH.PostHistoryTypeId IN (
        4,   -- Edit Title
        5,   -- Edit Body
        6,   -- Edit Tags
        10,  -- Post Closed
        11,  -- Post Reopened
        24   -- Suggested Edit Applied
    )
),
UserHistoryMetrics AS (
    -- Aggregate user-level metrics from post history analysis
    SELECT
        PECH.HistoryEventUserId AS UserId,
        COUNT(DISTINCT PECH.PostId) AS DistinctPostsWithHistory,
        SUM(CASE WHEN PECH.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS TotalEditsMade,
        SUM(CASE WHEN PECH.PostHistoryTypeId = 24 THEN 1 ELSE 0 END) AS TotalSuggestedEditsApplied,
        SUM(CASE WHEN PECH.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalPostsClosedByMe,
        SUM(CASE WHEN PECH.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalPostsReopenedByMe,
        -- Average duration between this user's consecutive events on *any* post they interacted with history
        AVG(EXTRACT(EPOCH FROM (PECH.EventDate - PECH.PreviousEventDate)) / 3600.0) AS AvgHoursBetweenMyPostEvents,
        -- Max length of history text for any event by this user
        MAX(PECH.HistoryTextLength) AS MaxHistoryTextLength
    FROM PostEditChangeHistory AS PECH
    WHERE PECH.HistoryEventUserId IS NOT NULL
    GROUP BY PECH.HistoryEventUserId
),
UserInteractionAggregates AS (
    -- Aggregate comment and vote activity per user, considering both given and received
    SELECT
        U.Id AS UserId,
        COALESCE(SUM(CASE WHEN C.UserId = U.Id THEN 1 ELSE 0 END), 0) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN C.UserId = U.Id THEN C.Score ELSE 0 END), 0) AS TotalCommentScore,
        COALESCE(SUM(CASE WHEN V.UserId = U.Id AND V.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS TotalFavoritesGiven, -- Bookmark
        -- Correlated subquery for votes received on posts owned by this user
        COALESCE((SELECT COUNT(V2.Id) FROM Votes AS V2 JOIN Posts AS P2 ON V2.PostId = P2.Id WHERE P2.OwnerUserId = U.Id AND V2.VoteTypeId = 2), 0) AS UpvotesReceivedOnPosts,
        COALESCE((SELECT COUNT(V3.Id) FROM Votes AS V3 JOIN Posts AS P3 ON V3.PostId = P3.Id WHERE P3.OwnerUserId = U.Id AND V3.VoteTypeId = 3), 0) AS DownvotesReceivedOnPosts,
        COALESCE(SUM(CASE WHEN V.UserId = U.Id AND V.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalUpvotesGivenCalculated,
        COALESCE(SUM(CASE WHEN V.UserId = U.Id AND V.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS TotalDownvotesGivenCalculated
    FROM Users AS U
    LEFT JOIN Comments AS C ON U.Id = C.UserId
    LEFT JOIN Votes AS V ON U.Id = V.UserId -- Votes made by user
    GROUP BY U.Id
),
UserBadgeSummary AS (
    -- Summarize badge counts per user
    SELECT
        B.UserId,
        COUNT(B.Id) AS TotalBadges,
        SUM(CASE WHEN B.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN B.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN B.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(CASE WHEN B.TagBased = TRUE THEN 1 ELSE 0 END) AS TagBasedBadges
    FROM Badges AS B
    GROUP BY B.UserId
)
-- Main query: Combine all CTEs to generate a comprehensive user activity profile
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.Views AS ProfileViews,
    U.UpVotes AS UserGivenUpVotesFromProfile, -- Note: This is from Users table directly, distinct from calculated ones
    U.DownVotes AS UserGivenDownVotesFromProfile,
    U.WebsiteUrl,
    U.Location,
    -- String manipulation for AboutMeSnippet, handling NULL and length constraints
    SUBSTRING(COALESCE(U.AboutMe, ''), 1, LEAST(LENGTH(COALESCE(U.AboutMe, '')), 150)) AS AboutMeSnippet,
    -- User Post Activity Metrics
    COALESCE(AUPS.TotalPostsInScope, 0) AS TotalPostsInRelevantTags,
    COALESCE(AUPS.TotalPostScoreInScope, 0) AS TotalPostScoreFromRelevantTags,
    COALESCE(AUPS.TotalPostViewsInScope, 0) AS TotalPostViewsFromRelevantTags,
    COALESCE(AUPS.QuestionCountInScope, 0) AS QuestionCountInRelevantTags,
    COALESCE(AUPS.AnswerCountInScope, 0) AS AnswerCountInRelevantTags,
    COALESCE(AUPS.TotalAnswersOnQuestionsOwned, 0) AS TotalAnswersOnQuestionsOwned,
    COALESCE(AUPS.AvgQuestionFavoriteCount, 0.0) AS AvgQuestionFavoriteCount,
    COALESCE(AUPS.PostDensityPerYear, 0.0) AS PostDensityPerYearInScope,
    -- User History Metrics
    COALESCE(UHM.TotalEditsMade, 0) AS TotalSelfEditsOnPosts,
    COALESCE(UHM.TotalSuggestedEditsApplied, 0) AS TotalSuggestedEditsAppliedToMyPosts,
    COALESCE(UHM.TotalPostsClosedByMe, 0) AS TotalPostsClosedByMe,
    COALESCE(UHM.TotalPostsReopenedByMe, 0) AS TotalPostsReopenedByMe,
    COALESCE(UHM.AvgHoursBetweenMyPostEvents, 0.0) AS AvgHoursBetweenMyPostEvents,
    COALESCE(UHM.MaxHistoryTextLength, 0) AS MaxHistoryTextLength,
    -- User Interaction Metrics
    COALESCE(UIA.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(UIA.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(UIA.TotalFavoritesGiven, 0) AS TotalFavoritesGivenByMe,
    COALESCE(UIA.UpvotesReceivedOnPosts, 0) AS UpvotesReceivedOnMyPosts,
    COALESCE(UIA.DownvotesReceivedOnPosts, 0) AS DownvotesReceivedOnMyPosts,
    COALESCE(UIA.TotalUpvotesGivenCalculated, 0) AS TotalUpvotesGivenCalculated,
    COALESCE(UIA.TotalDownvotesGivenCalculated, 0) AS TotalDownvotesGivenCalculated,
    -- User Badge Metrics
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBS.TagBasedBadges, 0) AS TagBasedBadges,
    -- String expressions and NULL logic
    TRIM(REPLACE(REPLACE(REPLACE(UPPER(U.DisplayName), ' ', ''), '.', ''), '-', '')) AS NormalizedDisplayName,
    COALESCE(NULLIF(U.EmailHash, ''), 'NO_EMAIL_HASH_PROVIDED') AS EmailHashStatus,
    COALESCE(NULLIF(U.Location, ''), 'Earth') AS NormalizedLocation,
    -- Complicated calculation for a composite User Activity Score
    (
        U.Reputation * 0.25 +                                         -- Reputation weight
        COALESCE(AUPS.TotalPostsInScope, 0) * 5 +                     -- Posts count in relevant tags
        COALESCE(AUPS.TotalPostScoreInScope, 0) * 0.1 +               -- Post score contribution
        COALESCE(UHM.TotalEditsMade, 0) * 3 +                         -- Self-edits count
        COALESCE(UIA.TotalCommentsMade, 0) * 2 +                      -- Comments made
        COALESCE(UIA.UpvotesReceivedOnPosts, 0) * 0.75 +              -- Upvotes on posts
        COALESCE(UIA.DownvotesReceivedOnPosts, 0) * -0.3 +            -- Downvotes on posts (negative impact)
        (COALESCE(UBS.GoldBadges, 0) * 100 + COALESCE(UBS.SilverBadges, 0) * 30 + COALESCE(UBS.BronzeBadges, 0) * 10) + -- Badge value
        COALESCE(U.Views, 0) * 0.01 +                                 -- Profile views
        (CASE WHEN U.WebsiteUrl IS NOT NULL THEN 20 ELSE 0 END) +     -- Bonus for having a website
        (CASE WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 100 THEN 25 ELSE 0 END) + -- Bonus for detailed AboutMe
        (COALESCE(AUPS.PostDensityPerYear, 0) * 10) +                 -- Post frequency bonus
        (CASE WHEN U.LastAccessDate > NOW() - INTERVAL '3 months' THEN 50 ELSE 0 END) -- Recency bonus
    ) AS UserActivityScore,
    -- Window Function: Rank users based on their activity score
    RANK() OVER (ORDER BY (
        U.Reputation * 0.25 +
        COALESCE(AUPS.TotalPostsInScope, 0) * 5 +
        COALESCE(AUPS.TotalPostScoreInScope, 0) * 0.1 +
        COALESCE(UHM.TotalEditsMade, 0) * 3 +
        COALESCE(UIA.TotalCommentsMade, 0) * 2 +
        COALESCE(UIA.UpvotesReceivedOnPosts, 0) * 0.75 +
        COALESCE(UIA.DownvotesReceivedOnPosts, 0) * -0.3 +
        (COALESCE(UBS.GoldBadges, 0) * 100 + COALESCE(UBS.SilverBadges, 0) * 30 + COALESCE(UBS.BronzeBadges, 0) * 10) +
        COALESCE(U.Views, 0) * 0.01 +
        (CASE WHEN U.WebsiteUrl IS NOT NULL THEN 20 ELSE 0 END) +
        (CASE WHEN U.AboutMe IS NOT NULL AND LENGTH(U.AboutMe) > 100 THEN 25 ELSE 0 END) +
        (COALESCE(AUPS.PostDensityPerYear, 0) * 10) +
        (CASE WHEN U.LastAccessDate > NOW() - INTERVAL '3 months' THEN 50 ELSE 0 END)
    ) DESC, U.Id) AS OverallActivityRank,
    -- Correlated Subquery: Count user's questions with accepted answers
    (SELECT COUNT(DISTINCT P_acc.Id)
     FROM Posts AS P_acc
     WHERE P_acc.OwnerUserId = U.Id
       AND P_acc.PostTypeId = 1
       AND P_acc.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers,
    -- Correlated Subquery: Count recent close votes from this user on duplicate questions
    (SELECT COUNT(PH_dup.Id)
     FROM PostHistory AS PH_dup
     WHERE PH_dup.UserId = U.Id
       AND PH_dup.PostHistoryTypeId = 10 -- Post Closed
       AND PH_dup.CreationDate > NOW() - INTERVAL '180 days'
       AND PH_dup.Comment ILIKE '%duplicate%') AS RecentDuplicateCloseVotes

FROM Users AS U
LEFT JOIN ActiveUserPostSummary AS AUPS ON U.Id = AUPS.UserId
LEFT JOIN UserHistoryMetrics AS UHM ON U.Id = UHM.UserId
LEFT JOIN UserInteractionAggregates AS UIA ON U.Id = UIA.UserId
LEFT JOIN UserBadgeSummary AS UBS ON U.Id = UBS.UserId

WHERE U.Reputation > 7500
  AND U.CreationDate > '2012-01-01'
  AND (U.DisplayName IS NOT NULL AND LENGTH(U.DisplayName) BETWEEN 5 AND 40)
  -- Complicated predicate: Users with good reputation, active in last 6 months,
  -- and either gold badges or a significant number of edits, or high post count in scope
  AND (U.LastAccessDate > NOW() - INTERVAL '6 months'
       OR COALESCE(UBS.GoldBadges, 0) > 0
       OR COALESCE(UHM.TotalEditsMade, 0) > 150
       OR COALESCE(AUPS.TotalPostsInScope, 0) > 75)
  -- NULL logic: Ensure user account is not deleted (represented by AccountId presence)
  AND U.AccountId IS NOT NULL

UNION ALL

-- Second part of the query: Focus on users who are highly specialized or have strong community moderation involvement,
-- potentially outside the main activity scoring, using a different set of criteria.
SELECT
    U.Id AS UserId,
    U.DisplayName,
    U.Reputation,
    U.CreationDate AS UserCreationDate,
    U.LastAccessDate,
    U.Views AS ProfileViews,
    U.UpVotes AS UserGivenUpVotesFromProfile,
    U.DownVotes AS UserGivenDownVotesFromProfile,
    U.WebsiteUrl,
    U.Location,
    SUBSTRING(COALESCE(U.AboutMe, ''), 1, LEAST(LENGTH(COALESCE(U.AboutMe, '')), 150)) AS AboutMeSnippet,
    COALESCE(AUPS.TotalPostsInScope, 0) AS TotalPostsInRelevantTags,
    COALESCE(AUPS.TotalPostScoreInScope, 0) AS TotalPostScoreFromRelevantTags,
    COALESCE(AUPS.TotalPostViewsInScope, 0) AS TotalPostViewsFromRelevantTags,
    COALESCE(AUPS.QuestionCountInScope, 0) AS QuestionCountInRelevantTags,
    COALESCE(AUPS.AnswerCountInScope, 0) AS AnswerCountInRelevantTags,
    COALESCE(AUPS.TotalAnswersOnQuestionsOwned, 0) AS TotalAnswersOnQuestionsOwned,
    COALESCE(AUPS.AvgQuestionFavoriteCount, 0.0) AS AvgQuestionFavoriteCount,
    COALESCE(AUPS.PostDensityPerYear, 0.0) AS PostDensityPerYearInScope,
    COALESCE(UHM.TotalEditsMade, 0) AS TotalSelfEditsOnPosts,
    COALESCE(UHM.TotalSuggestedEditsApplied, 0) AS TotalSuggestedEditsAppliedToMyPosts,
    COALESCE(UHM.TotalPostsClosedByMe, 0) AS TotalPostsClosedByMe,
    COALESCE(UHM.TotalPostsReopenedByMe, 0) AS TotalPostsReopenedByMe,
    COALESCE(UHM.AvgHoursBetweenMyPostEvents, 0.0) AS AvgHoursBetweenMyPostEvents,
    COALESCE(UHM.MaxHistoryTextLength, 0) AS MaxHistoryTextLength,
    COALESCE(UIA.TotalCommentsMade, 0) AS TotalCommentsMade,
    COALESCE(UIA.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(UIA.TotalFavoritesGiven, 0) AS TotalFavoritesGivenByMe,
    COALESCE(UIA.UpvotesReceivedOnPosts, 0) AS UpvotesReceivedOnMyPosts,
    COALESCE(UIA.DownvotesReceivedOnPosts, 0) AS DownvotesReceivedOnMyPosts,
    COALESCE(UIA.TotalUpvotesGivenCalculated, 0) AS TotalUpvotesGivenCalculated,
    COALESCE(UIA.TotalDownvotesGivenCalculated, 0) AS TotalDownvotesGivenCalculated,
    COALESCE(UBS.TotalBadges, 0) AS TotalBadges,
    COALESCE(UBS.GoldBadges, 0) AS GoldBadges,
    COALESCE(UBS.SilverBadges, 0) AS SilverBadges,
    COALESCE(UBS.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(UBS.TagBasedBadges, 0) AS TagBasedBadges,
    TRIM(REPLACE(REPLACE(REPLACE(UPPER(U.DisplayName), ' ', ''), '.', ''), '-', '')) AS NormalizedDisplayName,
    COALESCE(NULLIF(U.EmailHash, ''), 'NO_EMAIL_HASH_PROVIDED') AS EmailHashStatus,
    COALESCE(NULLIF(U.Location, ''), 'Earth') AS NormalizedLocation,
    -- Different weighting for this branch, emphasizing moderation actions and specific badge types
    (
        U.Reputation * 0.1 +
        COALESCE(UHM.TotalPostsClosedByMe, 0) * 10 +           -- High bonus for closing posts
        COALESCE(UHM.TotalPostsReopenedByMe, 0) * 15 +          -- Even higher bonus for reopening
        (COALESCE(UBS.GoldBadges, 0) * 50 + COALESCE(UBS.SilverBadges, 0) * 20) + -- Focus on higher class badges
        COALESCE(UBS.TagBasedBadges, 0) * 5 +                  -- Bonus for tag-based expertise
        COALESCE(U.Views, 0) * 0.005                            -- Lower profile view weight
    ) AS UserActivityScore,
    RANK() OVER (ORDER BY (
        U.Reputation * 0.1 +
        COALESCE(UHM.TotalPostsClosedByMe, 0) * 10 +
        COALESCE(UHM.TotalPostsReopenedByMe, 0) * 15 +
        (COALESCE(UBS.GoldBadges, 0) * 50 + COALESCE(UBS.SilverBadges, 0) * 20) +
        COALESCE(UBS.TagBasedBadges, 0) * 5 +
        COALESCE(U.Views, 0) * 0.005
    ) DESC, U.Id) AS OverallActivityRank,
    (SELECT COUNT(DISTINCT P_acc.Id)
     FROM Posts AS P_acc
     WHERE P_acc.OwnerUserId = U.Id
       AND P_acc.PostTypeId = 1
       AND P_acc.AcceptedAnswerId IS NOT NULL) AS QuestionsWithAcceptedAnswers,
    (SELECT COUNT(PH_dup.Id)
     FROM PostHistory AS PH_dup
     WHERE PH_dup.UserId = U.Id
       AND PH_dup.PostHistoryTypeId = 10
       AND PH_dup.CreationDate > NOW() - INTERVAL '180 days'
       AND PH_dup.Comment ILIKE '%duplicate%') AS RecentDuplicateCloseVotes

FROM Users AS U
LEFT JOIN ActiveUserPostSummary AS AUPS ON U.Id = AUPS.UserId
LEFT JOIN UserHistoryMetrics AS UHM ON U.Id = UHM.UserId
LEFT JOIN UserInteractionAggregates AS UIA ON U.Id = UIA.UserId
LEFT JOIN UserBadgeSummary AS UBS ON U.Id = UBS.UserId

WHERE U.Reputation >= 20000 -- Higher reputation threshold
  AND U.LastAccessDate > NOW() - INTERVAL '1 year'
  AND COALESCE(UHM.TotalPostsClosedByMe, 0) + COALESCE(UHM.TotalPostsReopenedByMe, 0) > 10 -- Focus on moderation activity
  -- Exclude users who primarily focus on very old content (heuristic)
  AND NOT EXISTS (SELECT 1 FROM Posts P_old WHERE P_old.OwnerUserId = U.Id AND P_old.CreationDate < '2010-01-01' HAVING COUNT(P_old.Id) > 50)
  AND U.AccountId IS NOT NULL
ORDER BY UserActivityScore DESC, UserId
LIMIT 1000;
