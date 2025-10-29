-- {"query": "1019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3217} 

WITH PopularTags AS (
    -- Identifies the top 10 most active and highly-scored tags by analyzing questions
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
        COUNT(p.Id) AS QuestionCount,
        AVG(p.Score) AS AverageScore
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Focus on questions
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2 -- Exclude empty or malformed tag strings
    GROUP BY TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
    HAVING COUNT(p.Id) > 100 -- Only tags with substantial activity
    ORDER BY COUNT(p.Id) DESC, AVG(p.Score) DESC
    LIMIT 10
),
PostEditHistorySummary AS (
    -- Summarizes revision history for each post, counting unique editors, edits, closes, and reopens.
    -- Also identifies if a post was ever closed and subsequently reopened.
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits/rollbacks
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS FirstEditDate,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS LastCloseDate,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 11) AS LastReopenDate,
        MAX(CASE WHEN ph_close.PostHistoryTypeId = 10 AND ph_reopen.PostHistoryTypeId = 11 AND ph_reopen.CreationDate > ph_close.CreationDate THEN 1 ELSE 0 END) AS WasClosedThenReopened
    FROM PostHistory ph
    LEFT JOIN PostHistory ph_close ON ph.PostId = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    LEFT JOIN PostHistory ph_reopen ON ph.PostId = ph_reopen.PostId AND ph_reopen.PostHistoryTypeId = 11
    GROUP BY ph.PostId
),
UserPostEditStats AS (
    -- Aggregates post edit history statistics per user, focusing on their questions.
    SELECT
        p.OwnerUserId AS UserId,
        AVG(pes.EditCount) AS AvgQuestionEditCount,
        MAX(pes.WasClosedThenReopened) AS HasAnyQuestionBeenClosedAndReopened
    FROM Posts p
    JOIN PostEditHistorySummary pes ON p.Id = pes.PostId
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserAnswerAcceptanceRates AS (
    -- Calculates the rate at which answers to a user's questions are accepted, along with average accepted answer score.
    SELECT
        q.OwnerUserId,
        COUNT(DISTINCT q.Id) AS TotalQuestionsAsked,
        SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswers,
        COALESCE(CAST(SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS NUMERIC) / COUNT(DISTINCT q.Id), 0) AS AcceptanceRate,
        AVG(a.Score) AS AvgAcceptedAnswerScore
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    WHERE q.PostTypeId = 1 -- Only questions
      AND q.OwnerUserId IS NOT NULL
    GROUP BY q.OwnerUserId
    HAVING COUNT(DISTINCT q.Id) >= 5 -- Only consider users who have asked at least 5 questions
),
UserBadgeClassCounts AS (
    -- Counts the total number of badges and categorizes them by class (Gold, Silver, Bronze) for each user.
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserCommentActivity AS (
    -- Summarizes comment activity per user, including total comments, total score, average score, and last comment date.
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserPostLinkAnalysis AS (
    -- Analyzes how often a user's questions or answers are linked to or marked as duplicates.
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN pl.LinkTypeId = 1 AND pl.PostId = p.Id THEN 1 ELSE 0 END) AS LinkedAsSource,
        SUM(CASE WHEN pl.LinkTypeId = 1 AND pl.RelatedPostId = p.Id THEN 1 ELSE 0 END) AS LinkedAsRelated,
        SUM(CASE WHEN pl.LinkTypeId = 3 AND pl.PostId = p.Id THEN 1 ELSE 0 END) AS DuplicatedAsSource,
        SUM(CASE WHEN pl.LinkTypeId = 3 AND pl.RelatedPostId = p.Id THEN 1 ELSE 0 END) AS DuplicatedAsRelated
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    WHERE p.PostTypeId IN (1, 2) -- Only questions or answers
      AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserTagPosts AS (
    -- Flattens questions' tags for easier joining and filtering by popular tags.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.Score,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.OwnerUserId IS NOT NULL
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
),
UserTagContributionsAggregated AS (
    -- Aggregates a user's contributions (question count and score) for popular tags.
    SELECT
        utp.UserId,
        STRING_AGG(DISTINCT utp.TagName || ' (' || COUNT(utp.PostId) || ')', '; ') AS TopTagContributionsString,
        COUNT(utp.PostId) AS TotalQuestionsInPopularTags,
        SUM(utp.Score) AS TotalScoreInPopularTags
    FROM UserTagPosts utp
    WHERE utp.TagName IN (SELECT TagName FROM PopularTags) -- Filter to only popular tags
    GROUP BY utp.UserId
    HAVING COUNT(utp.PostId) > 5 AND COUNT(DISTINCT utp.TagName) >= 2 -- Require significant contribution to multiple popular tags
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(ura.AcceptanceRate, 0) AS QuestionAcceptanceRate,
    COALESCE(ubc.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubc.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubc.BronzeBadges, 0) AS BronzeBadges,
    COALESCE(uca.TotalComments, 0) AS TotalCommentsMade,
    COALESCE(uca.AvgCommentScore, 0.0) AS AvgCommentScore,
    COALESCE(upla.LinkedAsSource, 0) AS QuestionsLinkedAsSource,
    COALESCE(upla.DuplicatedAsRelated, 0) AS QuestionsDuplicatedAsRelated,
    utca.TopTagContributionsString AS TopTagContributions,
    utca.TotalQuestionsInPopularTags,
    utca.TotalScoreInPopularTags,
    COALESCE(ues.AvgQuestionEditCount, 0.0) AS AvgQuestionEditCount,
    COALESCE(ues.HasAnyQuestionBeenClosedAndReopened, 0) AS HasAnyQuestionBeenClosedAndReopened,
    -- Window functions for ranking and comparison
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ubc.TotalBadges, 0) DESC) AS ReputationBadgeRank,
    NTILE(10) OVER (ORDER BY u.Views DESC) AS ViewsDecile,
    LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PrevUserReputationByCreationDate,
    LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS NextUserReputationByCreationDate,
    AVG(u.Reputation) OVER (PARTITION BY COALESCE(SUBSTRING(u.Location, 1, 5), 'Unknown')) AS AvgReputationInLocationPrefix,
    -- Complex calculated score combining various engagement metrics
    (COALESCE(ura.AcceptanceRate, 0) * 100 * (COALESCE(ubc.GoldBadges, 0) + COALESCE(ubc.SilverBadges, 0) * 0.5 + COALESCE(ubc.BronzeBadges, 0) * 0.25) + COALESCE(uca.AvgCommentScore, 0) + utca.TotalScoreInPopularTags / 100.0) AS UserEngagementScore,
    -- Correlated Subquery: Checks if the user has made a recent "clarification" comment on one of their own popular-tagged questions.
    EXISTS (
        SELECT 1
        FROM Comments c_inner
        JOIN UserTagPosts utp_inner ON c_inner.PostId = utp_inner.PostId
        WHERE c_inner.UserId = u.Id
          AND utp_inner.UserId = u.Id -- Comment made by user on their own post
          AND utp_inner.TagName IN (SELECT TagName FROM PopularTags) -- Post must be associated with a popular tag
          AND c_inner.CreationDate > NOW() - INTERVAL '6 months'
          AND c_inner.Text ILIKE '%clarification%'
        LIMIT 1
    ) AS HasRecentSelfClarificationComment,
    -- String manipulations and NULL handling for AboutMe and WebsiteUrl
    COALESCE(LEFT(u.AboutMe, 100), 'No "About Me" provided') AS AboutMeExcerpt,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%github.com%' THEN 'GitHub'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%linkedin.com%' THEN 'LinkedIn'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'StackOverflow'
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%twitter.com%' THEN 'Twitter'
        ELSE 'Other/None'
    END AS PrimaryWebsiteType,
    -- Date arithmetic for calculating years active
    EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / (60 * 60 * 24 * 365.25) AS YearsActive
FROM Users u
LEFT JOIN UserAnswerAcceptanceRates ura ON u.Id = ura.OwnerUserId
LEFT JOIN UserBadgeClassCounts ubc ON u.Id = ubc.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserPostLinkAnalysis upla ON u.Id = upla.UserId
INNER JOIN UserTagContributionsAggregated utca ON u.Id = utca.UserId -- Inner join to only include users with significant popular tag contributions
LEFT JOIN UserPostEditStats ues ON u.Id = ues.UserId
WHERE
    u.Reputation > 5000
    AND u.Views > 1000
    AND (u.Location IS NOT NULL AND u.Location ILIKE '%united states%' OR u.Location IS NULL) -- Example of NULL logic in predicate with string search
    AND u.CreationDate < NOW() - INTERVAL '2 year' -- User must have been active for at least 2 years
    AND COALESCE(ubc.TotalBadges, 0) >= 5 -- User must have at least 5 badges
    AND COALESCE(ura.AcceptanceRate, 0) > 0.10 -- User must have an acceptance rate greater than 10% for their questions
    AND NOT EXISTS ( -- Non-correlated subquery: Exclude users who recently earned a "student" badge
        SELECT 1
        FROM Badges b_recent
        WHERE b_recent.UserId = u.Id
          AND b_recent.Name ILIKE '%student%'
          AND b_recent.Date > NOW() - INTERVAL '1 year'
    )
ORDER BY
    UserEngagementScore DESC, ReputationBadgeRank
LIMIT 500;
