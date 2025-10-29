-- {"query": "1776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2970} 

WITH UserEngagementSummary AS (
    -- Summarizes user activity, including post counts, scores, and comment/vote activity
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p_all.Id) AS TotalPosts,
        SUM(CASE WHEN p_all.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p_all.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COALESCE(SUM(p_all.Score), 0) AS TotalPostScore,
        SUM(CASE WHEN p_all.PostTypeId = 1 AND p_all.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p_all.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q_parent WHERE q_parent.Id = p_all.ParentId AND q_parent.AcceptedAnswerId = p_all.Id) THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesGivenByOwner,
        NULLIF(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotesGiven,
        NULLIF(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotesGiven
    FROM Users u
    LEFT JOIN Posts p_all ON u.Id = p_all.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
PostHistoricalMetrics AS (
    -- Tracks the most recent body edit for each post
    SELECT
        ph.PostId,
        ph.UserId AS LastEditorUserId,
        ph.CreationDate AS LastEditDate,
        ph.PostHistoryTypeId,
        ph.Text AS BodySnapshot,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC, ph.Id DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
),
UserTopTags AS (
    -- Identifies the most frequent tags used by each user in their questions, excluding generic tags
    WITH TagOccurrences AS (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><'))) AS TagName,
            COUNT(*) AS TagCount
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.Tags !~* '(<c#>|<java>|<python>|<javascript>)' -- Exclude very common dev tags for variety
        GROUP BY p.OwnerUserId, TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')))
    )
    SELECT
        t.UserId,
        t.TagName,
        t.TagCount,
        ROW_NUMBER() OVER (PARTITION BY t.UserId ORDER BY t.TagCount DESC, t.TagName) as rn
    FROM TagOccurrences t
)
-- Main query combining all CTEs and adding window functions, complicated expressions, and set operators
SELECT
    'HighReputationActiveUser' AS UserCategory,
    ues.UserId,
    ues.UserName,
    ues.Reputation,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.AcceptedAnswersCount,
    ues.TotalPostScore,
    ptt.TagName AS MostFrequentQuestionTag,
    AVG(p.Score) OVER (PARTITION BY ues.UserId) AS AvgQuestionScore,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY ues.UserId) AS ClosedQuestionsCount,
    NULLIF(CAST(SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY ues.UserId) AS NUMERIC), 0) / NULLIF(CAST(ues.TotalQuestions AS NUMERIC), 0) AS PositiveQuestionRatio,
    (
        SELECT AVG(ans_p.Score)
        FROM Posts ans_p
        WHERE ans_p.OwnerUserId = ues.UserId
          AND ans_p.PostTypeId = 2 -- It's an answer
          AND EXISTS (
              SELECT 1
              FROM Posts q_check
              WHERE q_check.Id = ans_p.ParentId
                AND q_check.AcceptedAnswerId = ans_p.Id -- This answer was accepted for its parent question
          )
    ) AS AvgScoreOfAcceptedAnswers,
    (SELECT COUNT(DISTINCT badge.Id) FROM Badges badge WHERE badge.UserId = ues.UserId AND badge.Class = 1 AND badge.TagBased = FALSE) AS NonTagBasedGoldBadges,
    (
        SELECT r_hist.CreationDate
        FROM PostHistory r_hist
        WHERE r_hist.PostId = p.Id
          AND r_hist.PostHistoryTypeId = 11 -- Post Reopened
        ORDER BY r_hist.CreationDate DESC
        LIMIT 1
    ) AS LastPostReopenedDate,
    COALESCE(phm.LastEditDate, p.CreationDate) AS LastContentActivityDate,
    ROUND(EXTRACT(EPOCH FROM (NOW() - COALESCE(phm.LastEditDate, p.CreationDate))) / (3600 * 24), 2) AS DaysSinceLastContentActivity,
    NULLIF(CAST(ues.AcceptedAnswersCount AS NUMERIC), 0) / NULLIF(CAST(ues.TotalAnswers AS NUMERIC), 0) AS AcceptedAnswerRatio,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinksForQuestion,
    p.Title,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    LENGTH(p.Body) AS BodyLength,
    SUBSTRING(p.Body FROM 1 FOR 100) AS BodyExcerpt,
    CASE
        WHEN p.Body LIKE '%<pre><code>%' OR p.Body LIKE '%<source>%' THEN 'ContainsCodeBlock'
        WHEN p.Body LIKE '%<strong>%' OR p.Body LIKE '%<em>%' THEN 'ContainsFormatting'
        WHEN p.Body IS NULL OR p.Body = '' THEN 'EmptyBody'
        ELSE 'PlainBody'
    END AS BodyContentStyle,
    CAST(ues.TotalCommentsMade AS NUMERIC) / NULLIF(CAST(ues.TotalPosts AS NUMERIC), 0) AS CommentsPerPostRatio,
    ues.UpVotesGiven,
    ues.DownVotesGiven,
    RANK() OVER (PARTITION BY ues.UserCategory ORDER BY ues.Reputation DESC, ues.LastAccessDate DESC) AS UserRank
FROM UserEngagementSummary ues
INNER JOIN Posts p ON ues.UserId = p.OwnerUserId
LEFT JOIN PostHistoricalMetrics phm ON p.Id = phm.PostId AND phm.rn = 1
LEFT JOIN UserTopTags ptt ON ues.UserId = ptt.UserId AND ptt.rn = 1
WHERE
    ues.Reputation >= 10000 AND ues.TotalQuestions >= 50 AND ues.TotalAnswers >= 100
    AND p.PostTypeId = 1 -- Only consider questions for this part
    AND p.CreationDate > (NOW() - INTERVAL '2 year') -- Questions within the last 2 years
    AND ues.AcceptedAnswersCount > 0
    AND p.Score > 5
    AND p.ViewCount > 1000
    AND p.LastActivityDate IS NOT NULL AND p.LastActivityDate > (NOW() - INTERVAL '6 months') -- Recently active posts
UNION ALL
SELECT
    'LowReputationRecentUser' AS UserCategory,
    ues.UserId,
    ues.UserName,
    ues.Reputation,
    ues.TotalQuestions,
    ues.TotalAnswers,
    ues.AcceptedAnswersCount,
    ues.TotalPostScore,
    ptt.TagName AS MostFrequentQuestionTag,
    AVG(p.Score) OVER (PARTITION BY ues.UserId) AS AvgQuestionScore,
    SUM(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END) OVER (PARTITION BY ues.UserId) AS ClosedQuestionsCount,
    NULLIF(CAST(SUM(CASE WHEN p.Score > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY ues.UserId) AS NUMERIC), 0) / NULLIF(CAST(ues.TotalQuestions AS NUMERIC), 0) AS PositiveQuestionRatio,
    (
        SELECT AVG(ans_p.Score)
        FROM Posts ans_p
        WHERE ans_p.OwnerUserId = ues.UserId
          AND ans_p.PostTypeId = 2
          AND EXISTS (
              SELECT 1
              FROM Posts q_check
              WHERE q_check.Id = ans_p.ParentId
                AND q_check.AcceptedAnswerId = ans_p.Id
          )
    ) AS AvgScoreOfAcceptedAnswers,
    (SELECT COUNT(DISTINCT badge.Id) FROM Badges badge WHERE badge.UserId = ues.UserId AND badge.Class = 1 AND badge.TagBased = FALSE) AS NonTagBasedGoldBadges,
    (
        SELECT r_hist.CreationDate
        FROM PostHistory r_hist
        WHERE r_hist.PostId = p.Id
          AND r_hist.PostHistoryTypeId = 11
        ORDER BY r_hist.CreationDate DESC
        LIMIT 1
    ) AS LastPostReopenedDate,
    COALESCE(phm.LastEditDate, p.CreationDate) AS LastContentActivityDate,
    ROUND(EXTRACT(EPOCH FROM (NOW() - COALESCE(phm.LastEditDate, p.CreationDate))) / (3600 * 24), 2) AS DaysSinceLastContentActivity,
    NULLIF(CAST(ues.AcceptedAnswersCount AS NUMERIC), 0) / NULLIF(CAST(ues.TotalAnswers AS NUMERIC), 0) AS AcceptedAnswerRatio,
    (SELECT COUNT(DISTINCT pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinksForQuestion,
    p.Title,
    p.ViewCount,
    p.CommentCount,
    p.FavoriteCount,
    LENGTH(p.Body) AS BodyLength,
    SUBSTRING(p.Body FROM 1 FOR 100) AS BodyExcerpt,
    CASE
        WHEN p.Body LIKE '%<pre><code>%' OR p.Body LIKE '%<source>%' THEN 'ContainsCodeBlock'
        WHEN p.Body LIKE '%<strong>%' OR p.Body LIKE '%<em>%' THEN 'ContainsFormatting'
        WHEN p.Body IS NULL OR p.Body = '' THEN 'EmptyBody'
        ELSE 'PlainBody'
    END AS BodyContentStyle,
    CAST(ues.TotalCommentsMade AS NUMERIC) / NULLIF(CAST(ues.TotalPosts AS NUMERIC), 0) AS CommentsPerPostRatio,
    ues.UpVotesGiven,
    ues.DownVotesGiven,
    RANK() OVER (PARTITION BY ues.UserCategory ORDER BY ues.Reputation DESC, ues.LastAccessDate DESC) AS UserRank
FROM UserEngagementSummary ues
INNER JOIN Posts p ON ues.UserId = p.OwnerUserId
LEFT JOIN PostHistoricalMetrics phm ON p.Id = phm.PostId AND phm.rn = 1
LEFT JOIN UserTopTags ptt ON ues.UserId = ptt.UserId AND ptt.rn = 1
WHERE
    ues.Reputation < 500 AND ues.TotalQuestions >= 5 AND ues.TotalAnswers >= 10
    AND p.PostTypeId = 1 -- Only consider questions for this part
    AND p.CreationDate > (NOW() - INTERVAL '1 year') -- Questions within the last year
    AND p.ViewCount > 100
    AND ues.TotalPosts > 0
    AND ues.UserCreationDate > (NOW() - INTERVAL '3 year') -- Relatively new users
ORDER BY UserCategory, UserRank, DaysSinceLastContentActivity ASC
LIMIT 1000;
