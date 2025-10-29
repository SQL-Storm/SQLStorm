-- {"query": "1654.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3055} 

WITH UserAggregateStats AS (
    -- Aggregates various statistics for each user, including post counts, scores, and last activity.
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT p_q.Id) AS TotalQuestionsAsked,
        COUNT(DISTINCT p_a.Id) AS TotalAnswersGiven,
        COALESCE(SUM(p_q.Score), 0) AS TotalQuestionScore,
        COALESCE(SUM(p_a.Score), 0) AS TotalAnswerScore,
        COALESCE(SUM(p_q.ViewCount), 0) AS TotalQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MAX(COALESCE(p.LastActivityDate, p.CreationDate, c.CreationDate, u.LastAccessDate)) AS LatestActivityDate,
        COUNT(DISTINCT b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Posts p_q ON u.Id = p_q.OwnerUserId AND p_q.PostTypeId = 1 -- Questions
    LEFT JOIN Posts p_a ON u.Id = p_a.OwnerUserId AND p_a.PostTypeId = 2 -- Answers
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId -- All posts for LastActivityDate to get the latest activity regardless of type
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id
),
PostComplexMetrics AS (
    -- Calculates various complex metrics for each post, including edit counts, link counts, vote counts, and tag analysis.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        p.AcceptedAnswerId,
        COUNT(DISTINCT ph_edit.Id) AS EditCount,
        COUNT(DISTINCT pl_src.Id) + COUNT(DISTINCT pl_rel.Id) AS TotalLinkCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        COUNT(DISTINCT cmt.Id) AS CommentCount,
        MAX(cmt.CreationDate) AS LastCommentDate,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN TRUE ELSE FALSE END AS HasAcceptedAnswer,
        p.CommunityOwnedDate IS NOT NULL AS IsCommunityOwned,
        EXTRACT(DAY FROM (NOW() - p.CreationDate)) AS DaysSinceCreation,
        -- String expression to count tags, handling potential NULLs or empty tag strings
        COALESCE(ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1), 0) AS TagCount,
        -- Window function to rank posts by score within their respective PostType.
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostScoreRankType
    FROM Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId IN (4, 5, 6, 8) -- Edit Title, Edit Body, Edit Tags, Rollback Body
    LEFT JOIN PostLinks pl_src ON p.Id = pl_src.PostId
    LEFT JOIN PostLinks pl_rel ON p.Id = pl_rel.RelatedPostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    LEFT JOIN Comments cmt ON p.Id = cmt.PostId
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags, p.AcceptedAnswerId, p.CommunityOwnedDate
),
BadgePrestige AS (
    -- Identifies the highest class badge (Gold=1, Silver=2) for each user and predicts the next badge class.
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeAwardDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS rn_prestige, -- Rank 1 for the highest prestige badge (lowest Class number)
        LEAD(b.Class, 1, 99) OVER (PARTITION BY b.UserId ORDER BY b.Date ASC) AS NextBadgeClass -- Predict the class of the next awarded badge
    FROM Badges b
    WHERE b.Class IN (1, 2) -- Only consider Gold or Silver badges for prestige analysis
),
UserPostTagDetails AS (
    -- Aggregates distinct prefixes of tags from high-scoring questions for each user.
    SELECT
        pcm.OwnerUserId AS UserId,
        STRING_AGG(DISTINCT LOWER(SUBSTRING(TRIM(UNNEST(string_to_array(substring(p_tags.Tags, 2, LENGTH(p_tags.Tags)-2), '><'))), 1, 10)), ';') AS TopQuestionTagPrefixes
    FROM PostComplexMetrics pcm
    JOIN Posts p_tags ON p_tags.Id = pcm.PostId
    WHERE pcm.PostTypeId = 1 AND pcm.Score > 100 AND p_tags.Tags IS NOT NULL AND LENGTH(p_tags.Tags) > 2
    GROUP BY pcm.OwnerUserId
),
QuestionAnswerAverageScore AS (
    -- Uses a set operator (UNION ALL) to calculate the average score for questions and answers separately.
    SELECT PostTypeId, AVG(Score) AS AverageScore FROM Posts WHERE PostTypeId = 1 GROUP BY PostTypeId
    UNION ALL
    SELECT PostTypeId, AVG(Score) AS AverageScore FROM Posts WHERE PostTypeId = 2 GROUP BY PostTypeId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersGiven,
    uas.TotalQuestionScore,
    uas.TotalAnswerScore,
    uas.TotalCommentsMade,
    uas.TotalBadges,
    uas.LatestActivityDate,
    AGE(NOW(), u.CreationDate) AS UserAgeSinceCreation,
    EXTRACT(DAY FROM (uas.LatestActivityDate - u.CreationDate)) AS DaysActiveSinceCreation,
    -- Complicated calculation with NULL logic for average scores
    COALESCE(CAST(uas.TotalQuestionScore AS NUMERIC) / NULLIF(uas.TotalQuestionsAsked, 0), 0) AS AvgQuestionScorePerUser,
    COALESCE(CAST(uas.TotalAnswerScore AS NUMERIC) / NULLIF(uas.TotalAnswersGiven, 0), 0) AS AvgAnswerScorePerUser,
    bp_gold.BadgeName AS HighestPrestigeBadge,
    bp_gold.BadgeAwardDate AS HighestPrestigeBadgeDate,
    bp_gold.NextBadgeClass AS ClassAfterHighestBadge,
    SUM(CASE WHEN pcm.PostTypeId = 1 AND pcm.EditCount > 3 THEN 1 ELSE 0 END) AS QuestionsWithHighEdits,
    SUM(CASE WHEN pcm.PostTypeId = 2 AND pcm.TotalLinkCount > 0 THEN 1 ELSE 0 END) AS AnswersWithLinks,
    MAX(pcm.Score) AS MaxPostScore,
    AVG(CAST(pcm.EditCount AS NUMERIC)) AS AvgPostEditCount,
    -- Correlated subquery example: Checks for specific post characteristics for the user.
    EXISTS (
        SELECT 1
        FROM PostComplexMetrics pcm_inner
        WHERE pcm_inner.OwnerUserId = u.Id
          AND pcm_inner.PostTypeId = 1
          AND pcm_inner.ViewCount > 5000
          AND COALESCE(pcm_inner.AnswerCount, 0) < 2
    ) AS HasHighlyViewedUnansweredQuestion,
    -- Non-correlated subquery example: Compares user's average score to a global average derived from a CTE.
    COALESCE(CAST(uas.TotalQuestionScore AS NUMERIC) / NULLIF(uas.TotalQuestionsAsked, 0), 0) - (SELECT AverageScore FROM QuestionAnswerAverageScore WHERE PostTypeId = 1) AS QuestionScoreVsGlobalAvgDiff,
    -- Complex ratio calculation using COALESCE and NULLIF
    COALESCE(
        CAST(SUM(CASE WHEN pcm.PostTypeId = 1 THEN pcm.ViewCount ELSE 0 END) AS NUMERIC) / NULLIF(SUM(CASE WHEN pcm.PostTypeId = 1 THEN pcm.AnswerCount ELSE 0 END), 0),
        0
    ) AS QuestionViewToAnswerRatio,
    -- Window function: Rolling average of reputation for previous users based on creation date.
    AVG(u.Reputation) OVER (ORDER BY u.CreationDate ASC ROWS BETWEEN 10 PRECEDING AND CURRENT ROW) AS RollingAvgReputationLast10Users,
    -- Window function: Rank users by their total reputation.
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS UserReputationRank,
    uptd.TopQuestionTagPrefixes,
    -- NULL logic and string expression in a CASE predicate.
    CASE
        WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unspecified'
        WHEN u.Location ILIKE '%London%' OR u.Location ILIKE '%NYC%' OR u.Location ILIKE '%San Francisco%' THEN 'Major Tech Hub'
        WHEN LENGTH(u.Location) > 20 AND u.AboutMe IS NOT NULL THEN 'Detailed Info User'
        ELSE 'Other Location'
    END AS LocationDetailCategory,
    -- Complicated calculation involving vote difference and post age.
    COALESCE(
        (CAST(SUM(pcm.UpVotesCount) AS NUMERIC) - SUM(pcm.DownVotesCount)) / NULLIF(SUM(pcm.DaysSinceCreation), 0),
        0
    ) AS NetVoteRatePerDay,
    SUM(CASE WHEN pcm.LastCommentDate > pcm.CreationDate + INTERVAL '30 days' AND pcm.CommentCount > 5 THEN 1 ELSE 0 END) AS LateActiveCommentPosts,
    COUNT(DISTINCT CASE WHEN pcm.PostTypeId = 1 AND pcm.HasAcceptedAnswer IS TRUE THEN pcm.PostId END) AS QuestionsWithAcceptedAnswers,
    -- Average favorites per post for a user, handling division by zero.
    COALESCE(CAST(SUM(pcm.FavoriteCount) AS NUMERIC) / NULLIF(COUNT(DISTINCT pcm.PostId), 0), 0) AS AvgFavoritesPerPost
FROM Users u
LEFT JOIN UserAggregateStats uas ON u.Id = uas.UserId
LEFT JOIN PostComplexMetrics pcm ON u.Id = pcm.OwnerUserId
LEFT JOIN BadgePrestige bp_gold ON u.Id = bp_gold.UserId AND bp_gold.rn_prestige = 1 -- Get the highest prestige badge for the user
LEFT JOIN UserPostTagDetails uptd ON u.Id = uptd.UserId
WHERE
    u.Reputation >= 10000 -- Focus on highly reputed users.
    AND u.Views > 100 -- Users with significant profile views.
    AND u.LastAccessDate >= NOW() - INTERVAL '6 months' -- Recently active users.
    AND (u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50) -- Users who provided a non-trivial "About Me" section.
    -- Correlated subquery to check for specific tag presence and score on questions.
    AND EXISTS (
        SELECT 1
        FROM Posts p_perf
        WHERE p_perf.OwnerUserId = u.Id
          AND p_perf.PostTypeId = 1
          AND p_perf.Tags ILIKE '%<performance>%'
          AND p_perf.Score > 50
    )
GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, uas.TotalQuestionsAsked, uas.TotalAnswersGiven,
    uas.TotalQuestionScore, uas.TotalAnswerScore, uas.TotalCommentsMade, uas.TotalBadges,
    uas.LatestActivityDate, bp_gold.BadgeName, bp_gold.BadgeAwardDate, bp_gold.NextBadgeClass,
    uptd.TopQuestionTagPrefixes
HAVING
    COUNT(pcm.PostId) > 10 -- Ensure the user has at least 10 posts contributing to the metrics.
    AND SUM(CASE WHEN pcm.HasAcceptedAnswer THEN 1 ELSE 0 END) >= 2 -- At least two accepted answers (or questions with accepted answers).
    AND AVG(CAST(pcm.UpVotesCount AS NUMERIC)) > 5 -- Average of more than 5 upvotes per post to filter for generally positive contributors.
ORDER BY
    UserReputationRank ASC, NetVoteRatePerDay DESC
LIMIT 500;
