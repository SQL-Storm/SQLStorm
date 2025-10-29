-- {"query": "1463.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3258} 

WITH UserEngagement AS (
    -- Calculate detailed user engagement metrics over the last 5 years, including various activity counts and a composite score.
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Reputation,
        U.CreationDate AS UserCreationDate,
        U.LastAccessDate,
        U.UpVotes,
        U.DownVotes,
        U.Views AS UserProfileViews,
        COUNT(DISTINCT P.Id) AS TotalPostsCreated,
        SUM(CASE WHEN P.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN P.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT C.Id) AS TotalCommentsMade,
        COUNT(DISTINCT PH.Id) AS TotalPostHistoryEvents,
        SUM(COALESCE(V_bounty.BountyAmount, 0)) AS TotalBountyReceived,
        MAX(P.LastActivityDate) AS LastPostActivityDate,
        MAX(C.CreationDate) AS LastCommentActivityDate,
        -- A composite activity score, weighting different actions.
        (U.UpVotes * 2 + U.DownVotes + COUNT(DISTINCT P.Id) * 5 + COUNT(DISTINCT C.Id) * 3 + COUNT(DISTINCT PH.Id) * 0.5) AS ActivityScore,
        -- Days since user creation, handling potential NULLs from future dates (though unlikely).
        COALESCE(EXTRACT(EPOCH FROM (NOW() - U.CreationDate)) / 86400, 0) AS DaysSinceCreation
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId AND P.CreationDate >= (NOW() - INTERVAL '5 year')
    LEFT JOIN Comments AS C ON U.Id = C.UserId AND C.CreationDate >= (NOW() - INTERVAL '5 year')
    LEFT JOIN PostHistory AS PH ON U.Id = PH.UserId AND PH.CreationDate >= (NOW() - INTERVAL '5 year')
    LEFT JOIN Votes AS V_bounty ON U.Id = V_bounty.UserId AND V_bounty.VoteTypeId IN (8, 9) AND V_bounty.CreationDate >= (NOW() - INTERVAL '5 year') -- Bounty related votes
    GROUP BY
        U.Id, U.DisplayName, U.Reputation, U.CreationDate, U.LastAccessDate, U.UpVotes, U.DownVotes, U.Views
),
PostPerformanceSummary AS (
    -- Summarize post performance, including score, view counts, and acceptance status for questions.
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
        P.AcceptedAnswerId,
        P.ClosedDate,
        P.LastActivityDate,
        -- Determine if a question has an accepted answer.
        CASE WHEN P.PostTypeId = 1 AND P.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        -- Categorize posts based on a combination of score and view count.
        CASE
            WHEN P.Score >= 100 AND P.ViewCount >= 10000 THEN 'Highly Viral'
            WHEN P.Score >= 50 AND P.ViewCount >= 5000 THEN 'Very Popular'
            WHEN P.Score >= 10 AND P.ViewCount >= 1000 THEN 'Popular'
            WHEN P.Score > 0 OR P.ViewCount > 100 THEN 'Modestly Engaged'
            ELSE 'Niche/New'
        END AS PostPopularityCategory,
        -- Calculate score per view, handling division by zero.
        CAST(P.Score AS NUMERIC) / NULLIF(P.ViewCount, 0) AS ScorePerView,
        -- Correlated subquery to find the latest comment creation date for each post.
        (SELECT MAX(C_sub.CreationDate) FROM Comments AS C_sub WHERE C_sub.PostId = P.Id AND C_sub.CreationDate >= (NOW() - INTERVAL '5 year')) AS LatestCommentDateForPost
    FROM Posts AS P
    WHERE P.CreationDate >= (NOW() - INTERVAL '5 year') -- Focus on recent posts
),
BadgeMilestoneAnalysis AS (
    -- Analyze user badge acquisition patterns, focusing on Gold and Silver badges.
    SELECT
        B.UserId,
        B.Name AS BadgeName,
        B.Date AS BadgeDate,
        B.Class AS BadgeClass,
        -- Calculate the time difference (in days) to the previous badge for the same user.
        EXTRACT(EPOCH FROM (B.Date - LAG(B.Date) OVER (PARTITION BY B.UserId ORDER BY B.Date))) / 86400 AS DaysSincePreviousBadge,
        -- Rank badges within each class for each user, ordering by date.
        ROW_NUMBER() OVER (PARTITION BY B.UserId, B.Class ORDER BY B.Date) AS BadgeClassRank
    FROM Badges AS B
    WHERE B.Class IN (1, 2) AND B.Date >= (NOW() - INTERVAL '5 year')
),
QuestionTagUsage AS (
    -- Extract and count distinct tags used by questions, filtering for common tags.
    SELECT
        P.Id AS PostId,
        P.OwnerUserId,
        TRIM(UNNEST(string_to_array(SUBSTRING(P.Tags FROM 2 FOR LENGTH(P.Tags) - 2), '><'))) AS TagName
    FROM Posts AS P
    WHERE P.PostTypeId = 1 AND P.Tags IS NOT NULL AND LENGTH(P.Tags) > 2 AND P.CreationDate >= (NOW() - INTERVAL '5 year')
),
DuplicateQuestionImpact AS (
    -- Aggregate information on questions linked as duplicates.
    SELECT
        PL.RelatedPostId AS OriginalPostId, -- The post identified as the original
        PL.PostId AS DuplicatePostId,      -- The post marked as a duplicate
        P_orig.CreationDate AS OriginalCreationDate,
        P_orig.Score AS OriginalScore,
        P_dup.CreationDate AS DuplicateCreationDate,
        P_dup.Score AS DuplicateScore,
        DATEDIFF('day', P_orig.CreationDate, P_dup.CreationDate) AS DaysUntilDuplicated
    FROM PostLinks AS PL
    JOIN Posts AS P_orig ON PL.RelatedPostId = P_orig.Id
    JOIN Posts AS P_dup ON PL.PostId = P_dup.Id
    WHERE PL.LinkTypeId = 3 AND P_orig.CreationDate >= (NOW() - INTERVAL '5 year') -- LinkType 3 for Duplicates
),
UserMonthlyActivity AS (
    -- Calculate monthly post and comment counts for users, then rank them.
    SELECT
        U.Id AS UserId,
        TO_CHAR(DATE_TRUNC('month', P.CreationDate), 'YYYY-MM') AS ActivityMonth,
        COUNT(DISTINCT P.Id) AS MonthlyPosts,
        COUNT(DISTINCT C.Id) AS MonthlyComments,
        SUM(P.Score) AS MonthlyPostScore,
        -- Rank users by their monthly post count within each month.
        ROW_NUMBER() OVER (PARTITION BY TO_CHAR(DATE_TRUNC('month', P.CreationDate), 'YYYY-MM') ORDER BY COUNT(DISTINCT P.Id) DESC) AS MonthlyPostRank
    FROM Users AS U
    LEFT JOIN Posts AS P ON U.Id = P.OwnerUserId AND P.CreationDate >= (NOW() - INTERVAL '1 year')
    LEFT JOIN Comments AS C ON U.Id = C.UserId AND C.CreationDate >= (NOW() - INTERVAL '1 year')
    WHERE P.Id IS NOT NULL OR C.Id IS NOT NULL -- Only users with activity
    GROUP BY U.Id, TO_CHAR(DATE_TRUNC('month', P.CreationDate), 'YYYY-MM')
)
-- Main query: Combines and analyzes data from the CTEs.
SELECT
    UE.UserId,
    UE.DisplayName,
    UE.Reputation,
    UE.ActivityScore,
    UE.DaysSinceCreation,
    UE.TotalPostsCreated,
    UE.QuestionsAsked,
    UE.AnswersGiven,
    UE.TotalCommentsMade,
    COALESCE(UE.TotalBountyReceived, 0) AS TotalBountyReceived,
    -- Average score per view for posts owned by the user, using a window function.
    AVG(PPS.ScorePerView) OVER (PARTITION BY UE.UserId) AS AvgPostScorePerView,
    -- Count of posts with an accepted answer, showing NULL logic for no such posts.
    COUNT(PPS.PostId) FILTER (WHERE PPS.HasAcceptedAnswer IS TRUE) AS AcceptedAnswerPostsCount,
    -- The category of the most popular question (if any) by the user.
    MAX(PPS.PostPopularityCategory) FILTER (WHERE PPS.PostTypeId = 1) AS UsersMostPopularQuestionCategory,
    -- Count distinct tags used by the user in their questions, using a correlated subquery.
    (SELECT COUNT(DISTINCT QTA_sub.TagName) FROM QuestionTagUsage AS QTA_sub WHERE QTA_sub.OwnerUserId = UE.UserId) AS DistinctTagsUsedInQuestions,
    COUNT(DISTINCT BMA.BadgeName) AS TotalUniqueBadges,
    MAX(BMA.BadgeDate) AS LatestBadgeDate,
    -- Average days between Gold badges (if any), handling potential division by zero or NULLs.
    COALESCE(AVG(BMA.DaysSincePreviousBadge) FILTER (WHERE BMA.BadgeClass = 1), 0) AS AvgDaysBetweenGoldBadges,
    -- Complex string expression combining user details and activity summary.
    CONCAT_WS(' | ',
        'Rep: ' || UE.Reputation,
        'Posts: ' || UE.TotalPostsCreated,
        'Comments: ' || UE.TotalCommentsMade,
        'Activity: ' || CASE
            WHEN UE.QuestionsAsked > UE.AnswersGiven THEN 'Question-Oriented'
            WHEN UE.AnswersGiven > UE.QuestionsAsked THEN 'Answer-Oriented'
            ELSE 'Balanced Contributor'
        END,
        'Last Active: ' || TO_CHAR(COALESCE(UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastAccessDate), 'YYYY-MM-DD')
    ) AS UserActivitySummary,
    -- Check if the user has a 'Highly Viral' question with an accepted answer.
    BOOL_OR(PPS.PostPopularityCategory = 'Highly Viral' AND PPS.PostTypeId = 1 AND PPS.HasAcceptedAnswer) AS HasHighlyViralAcceptedQuestion,
    -- Sum of scores of questions that were marked as duplicates of this user's questions.
    COALESCE(SUM(DQI.DuplicateScore) FILTER (WHERE DQI.OriginalPostId = PPS.PostId), 0) AS TotalDuplicateScoreImpact,
    -- Number of times this user's questions were identified as originals for duplicates.
    COUNT(DISTINCT DQI.DuplicatePostId) FILTER (WHERE DQI.OriginalPostId = PPS.PostId) AS CountOriginalsDuplicated,
    -- Find users who were top 10 posters in any month, combined with general active users.
    (SELECT MAX(TRUE) FROM UserMonthlyActivity AS UMA WHERE UMA.UserId = UE.UserId AND UMA.MonthlyPostRank <= 10) AS WasTopMonthlyPoster,
    -- Example of a complicated numeric calculation with NULL logic for a "legacy score" based on old data.
    (UE.Reputation / NULLIF(UE.DaysSinceCreation, 0) * 100) + (UE.UpVotes - UE.DownVotes) * 0.5 + COALESCE(UE.UserProfileViews, 0) / 10 AS LegacyUserPerformanceIndex
FROM UserEngagement AS UE
LEFT JOIN PostPerformanceSummary AS PPS ON UE.UserId = PPS.OwnerUserId
LEFT JOIN BadgeMilestoneAnalysis AS BMA ON UE.UserId = BMA.UserId
-- FULL OUTER JOIN to connect general user activity with duplicate post impact, demonstrating NULL propagation and handling.
FULL OUTER JOIN DuplicateQuestionImpact AS DQI ON PPS.PostId = DQI.OriginalPostId OR PPS.PostId = DQI.DuplicatePostId
WHERE
    UE.Reputation > 5000 -- Filter for higher reputation users
    AND UE.DaysSinceCreation > 730 -- Active for at least 2 years
    AND (
        LOWER(COALESCE(UE.DisplayName, '')) LIKE '%developer%' -- Users with 'developer' in their name
        OR LOWER(COALESCE(UE.DisplayName, '')) LIKE '%engineer%'
        OR UE.TotalPostsCreated > 100 -- Or made a substantial number of posts
    )
    AND NOT EXISTS (
        -- Correlated NOT EXISTS subquery to exclude users with very low activity recently (last 6 months)
        SELECT 1
        FROM Comments AS C_recent
        WHERE C_recent.UserId = UE.UserId
        AND C_recent.CreationDate > (NOW() - INTERVAL '6 month')
        HAVING COUNT(C_recent.Id) < 5
    )
GROUP BY
    UE.UserId, UE.DisplayName, UE.Reputation, UE.ActivityScore, UE.DaysSinceCreation,
    UE.TotalPostsCreated, UE.QuestionsAsked, UE.AnswersGiven, UE.TotalCommentsMade,
    UE.TotalBountyReceived, UE.LastPostActivityDate, UE.LastCommentActivityDate, UE.LastAccessDate,
    UE.UserProfileViews
HAVING
    COUNT(DISTINCT BMA.BadgeName) > 10 -- Users with more than 10 unique badges
    OR SUM(PPS.Score) FILTER (WHERE PPS.PostTypeId = 1) > 500 -- Or a high cumulative score from questions
    OR BOOL_OR(PPS.PostPopularityCategory = 'Highly Viral') -- Or has at least one highly viral post
ORDER BY
    UE.ActivityScore DESC, TotalUniqueBadges DESC, TotalDuplicateScoreImpact DESC
LIMIT 200;
