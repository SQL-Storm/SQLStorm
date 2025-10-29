-- {"query": "1943.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2827} 

WITH UserPostStats AS (
    -- Aggregates various statistics for each user related to their posts and comments.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        AVG(CAST(p.Score AS NUMERIC)) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalPostViews,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
PostQualityMetrics AS (
    -- Calculates various quality and engagement metrics for questions, including answer scores, comments, and tag analysis.
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(SUM(a.Score), 0) AS TotalAnswerScore,
        COALESCE(AVG(CAST(a.Score AS NUMERIC)), 0) AS AvgAnswerScore,
        COUNT(DISTINCT co.Id) AS QuestionCommentCount,
        -- Ratio of accepted answer score to total answer scores, demonstrating NULL handling and division logic.
        CASE
            WHEN SUM(a.Score) > 0 AND q.AcceptedAnswerId IS NOT NULL THEN
                COALESCE(MAX(CASE WHEN a.Id = q.AcceptedAnswerId THEN a.Score ELSE 0 END), 0) * 1.0 / SUM(a.Score)
            ELSE 0
        END AS AcceptedAnswerScoreRatio,
        -- Score per view, handling potential division by zero.
        COALESCE(q.Score * 1.0 / NULLIF(q.ViewCount, 0), 0) AS ScorePerView,
        -- String expression and predicate: Checks for specific 'complex' tags.
        (q.Tags LIKE '%<sql>%' OR q.Tags LIKE '%<database>%' OR q.Tags LIKE '%<performance>%') AS HasComplexTags
    FROM Posts q
    WHERE q.PostTypeId = 1 -- Focus on questions
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2 -- Join to answers
    LEFT JOIN Comments co ON q.Id = co.PostId -- Join to comments on the question
    GROUP BY q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.AcceptedAnswerId, q.Tags
),
UserBadgeProgression AS (
    -- Tracks user badge acquisition progression, using window functions to find sequence and time differences.
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        -- Window function: Assigns a sequence number to badges for each user.
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date) AS BadgeSequence,
        -- Window function: Ranks badges within each user, prioritizing Gold, then Silver, then Bronze by date.
        DENSE_RANK() OVER (PARTITION BY b.UserId ORDER BY b.Class, b.Date) AS RankWithinClass,
        -- Window function: Finds the date of the previous badge for each user.
        LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date) AS PreviousBadgeDate,
        -- Calculation: Days since the previous badge, handling the first badge case with COALESCE.
        COALESCE(EXTRACT(EPOCH FROM (b.Date - LAG(b.Date, 1) OVER (PARTITION BY b.UserId ORDER BY b.Date))) / 86400, 0) AS DaysSincePrevBadge,
        -- Calculation: Theoretical reputation gain per day up to the badge date (using current reputation as a proxy).
        u.Reputation * 1.0 / NULLIF(EXTRACT(EPOCH FROM (b.Date - u.CreationDate)) / 86400, 0) AS RepPerDayAtBadgeDate
    FROM Badges b
    JOIN Users u ON b.UserId = u.Id
    WHERE b.Class IN (1, 2) -- Focus on Gold and Silver badges
),
ContentEditorStats AS (
    -- Summarizes editing activity on posts, differentiating between owner edits and edits by other users.
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(ph.Id) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS ContentEditCount, -- Edits to Title, Body, or Tags
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate,
        p.OwnerUserId,
        -- Flags whether the owner edited the post or if other users did.
        MAX(CASE WHEN ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END) AS OwnerEdited,
        MAX(CASE WHEN ph.UserId IS NOT NULL AND ph.UserId != p.OwnerUserId THEN 1 ELSE 0 END) AS OtherUserEdited,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount -- Count close votes from history
    FROM PostHistory ph
    JOIN Posts p ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10) -- Initial creation, content edits, or close votes
    GROUP BY ph.PostId, ph.UserId, p.OwnerUserId
),
SelfCommentedAcceptedAnswers AS (
    -- Correlated subquery example: Identifies users who have commented on their own accepted answers.
    SELECT DISTINCT
        p.OwnerUserId AS UserId
    FROM Posts p
    WHERE p.PostTypeId = 2 -- An answer
      AND p.AcceptedAnswerId IS NOT NULL -- The question it answers has an accepted answer
      AND EXISTS ( -- Correlated EXISTS clause
          SELECT 1
          FROM Comments c
          WHERE c.PostId = p.Id
            AND c.UserId = p.OwnerUserId -- User commented on their own answer
      )
),
-- Aggregated CTEs to simplify the main query's joins
AggregatedQuestionMetrics AS (
    SELECT
        OwnerUserId AS UserId,
        SUM(QuestionScore) AS TotalOwnedQuestionScore,
        AVG(AvgAnswerScore) AS AvgAnswerScoreForOwnedQuestions,
        SUM(CASE WHEN HasComplexTags THEN 1 ELSE 0 END) AS ComplexTagQuestionCount
    FROM PostQualityMetrics
    GROUP BY OwnerUserId
),
AggregatedEditorMetrics AS (
    SELECT
        OwnerUserId AS UserId,
        COUNT(DISTINCT PostId) AS PostsEditedByOthersCount
    FROM ContentEditorStats
    WHERE OtherUserEdited = 1
    GROUP BY OwnerUserId
),
ProblematicPostSummary AS (
    -- Identifies posts that could be considered 'problematic' based on low scores, high comment counts, or multiple close votes.
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS ProblematicPostsCount
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
      AND (
          (p.Score < 0 AND p.CommentCount > 5) -- Low score and active comments
          OR
          EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 GROUP BY ph.PostId HAVING COUNT(ph.Id) >= 3) -- At least 3 close votes
      )
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS UserLocation, -- NULL logic: replaces NULL location with 'Unknown'
    us.TotalPosts,
    us.QuestionCount,
    us.AnswerCount,
    us.TotalPostScore,
    us.AvgPostScore,
    us.TotalCommentsMade,
    bprog.BadgeName AS LatestGoldSilverBadge,
    bprog.BadgeDate AS LatestBadgeDate,
    bprog.DaysSincePrevBadge AS DaysBetweenLastTwoBadges,
    bprog.RepPerDayAtBadgeDate,
    aqm.TotalOwnedQuestionScore,
    aqm.AvgAnswerScoreForOwnedQuestions,
    aqm.ComplexTagQuestionCount,
    aem.PostsEditedByOthersCount,
    -- Window function: Ranks users by reputation within their (possibly unknown) location.
    RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.Reputation DESC) AS RepRankInLocation,
    -- Result from the correlated subquery, indicating if the user has self-commented on an accepted answer.
    CASE WHEN scaa.UserId IS NOT NULL THEN TRUE ELSE FALSE END AS HasSelfCommentedAcceptedAnswer,
    -- Complicated calculation combining multiple user and content quality factors into an "Influence Score".
    (
        (u.Reputation * 0.1) +
        (COALESCE(us.TotalPostScore, 0) * 0.05) +
        (COALESCE(us.AvgPostScore, 0) * 10) +
        (COALESCE(bprog.BadgeSequence, 0) * 5) +
        (COALESCE(aqm.AvgAnswerScoreForOwnedQuestions, 0) * 2) +
        (CASE WHEN scaa.UserId IS NOT NULL THEN 50 ELSE 0 END) -
        (COALESCE(pps.ProblematicPostsCount, 0) * 10) -- Penalize for problematic posts
    ) AS InfluenceScore,
    -- String expression: Concatenates display name with a truncated 'AboutMe' section, handling NULLs and length.
    u.DisplayName || ' - ' || COALESCE(SUBSTRING(u.AboutMe FROM 1 FOR 50), '') || (CASE WHEN LENGTH(COALESCE(u.AboutMe, '')) > 50 THEN '...' ELSE '' END) AS UserBioSnippet,
    COALESCE(pps.ProblematicPostsCount, 0) AS ProblematicPostsCount
FROM Users u
LEFT JOIN UserPostStats us ON u.Id = us.UserId
LEFT JOIN ( -- Subquery using UNION ALL to get the latest Gold badge, or latest Silver if no Gold.
    SELECT UserId, BadgeName, BadgeDate, DaysSincePrevBadge, RepPerDayAtBadgeDate, BadgeSequence
    FROM UserBadgeProgression AS UBP_Gold
    WHERE RankWithinClass = 1 AND BadgeClass = 1 -- Latest Gold badge
    UNION ALL -- Set operator
    SELECT UserId, BadgeName, BadgeDate, DaysSincePrevBadge, RepPerDayAtBadgeDate, BadgeSequence
    FROM UserBadgeProgression AS UBP_Silver
    WHERE RankWithinClass = 1 AND BadgeClass = 2 AND NOT EXISTS (SELECT 1 FROM UserBadgeProgression WHERE UserId = UBP_Silver.UserId AND BadgeClass = 1) -- Latest Silver badge if no Gold exists for this user
) AS bprog ON u.Id = bprog.UserId
LEFT JOIN AggregatedQuestionMetrics aqm ON u.Id = aqm.UserId
LEFT JOIN AggregatedEditorMetrics aem ON u.Id = aem.UserId
LEFT JOIN SelfCommentedAcceptedAnswers scaa ON u.Id = scaa.UserId
LEFT JOIN ProblematicPostSummary pps ON u.Id = pps.UserId
ORDER BY
    InfluenceScore DESC, u.Reputation DESC
LIMIT 100;
