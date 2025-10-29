-- {"query": "1501.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2496} 

WITH UserPostHistorySummary AS (
    -- Summarize user-specific post history: edits, deletions, and closing actions for posts they own.
    SELECT
        ph.UserId,
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 END) AS EditCount, -- Title, Body, Tags edits/rollbacks
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14) THEN 1 END) AS CloseDeleteLockCount, -- Closed, Deleted, or Locked
        MAX(ph.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId BETWEEN 1 AND 100 -- Focus on common history types
    GROUP BY ph.UserId, ph.PostId
),
QuestionAnswerEngagement AS (
    -- Calculate detailed engagement metrics for questions and their associated answers and comments.
    SELECT
        p_q.Id AS QuestionId,
        p_q.OwnerUserId,
        p_q.Score AS QuestionScore,
        p_q.ViewCount AS QuestionViewCount,
        p_q.CommentCount AS QuestionCommentCount,
        p_q.CreationDate AS QuestionCreationDate,
        p_q.LastActivityDate AS QuestionLastActivityDate,
        p_q.Title AS QuestionTitle,
        p_q.Tags AS QuestionTags,
        COALESCE(p_q.AcceptedAnswerId, -1) AS AcceptedAnswerId, -- -1 if no accepted answer
        SUM(CASE WHEN p_a.Id IS NOT NULL THEN p_a.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT p_a.Id) AS AnswerCountActual,
        AVG(CASE WHEN p_a.Id IS NOT NULL THEN p_a.Score * 1.0 ELSE NULL END) AS AverageAnswerScore,
        MAX(p_a.CreationDate) AS LastAnswerDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnQuestion
    FROM Posts p_q
    LEFT JOIN Posts p_a ON p_q.Id = p_a.ParentId AND p_a.PostTypeId = 2 -- Answers to this question
    LEFT JOIN Comments c ON p_q.Id = c.PostId -- Comments directly on the question
    WHERE p_q.PostTypeId = 1 -- Only questions
      AND p_q.CreationDate >= '2018-01-01' -- Limit historical data for engagement calculation
    GROUP BY
        p_q.Id, p_q.OwnerUserId, p_q.Score, p_q.ViewCount, p_q.CommentCount,
        p_q.CreationDate, p_q.LastActivityDate, p_q.Title, p_q.Tags, p_q.AcceptedAnswerId
),
UserBadgeRank AS (
    -- Determine each user's highest class badge (Gold first, then Silver, then Bronze) and its award date.
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class IN (1, 2, 3) -- Gold, Silver, Bronze badges
),
UserRecentActivitySummary AS (
    -- Aggregate a user's latest activities: post, comment, and last access.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        MAX(u.LastAccessDate) AS UserLastAccessDate,
        MAX(p.CreationDate) AS LastPostCreationDate,
        MAX(c.CreationDate) AS LastCommentCreationDate,
        (SELECT p_latest.Title FROM Posts p_latest WHERE p_latest.OwnerUserId = u.Id ORDER BY p_latest.CreationDate DESC LIMIT 1) AS LatestPostTitle,
        (SELECT c_latest.Text FROM Comments c_latest WHERE c_latest.UserId = u.Id ORDER BY c_latest.CreationDate DESC LIMIT 1) AS LatestCommentText
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    GROUP BY u.Id, u.DisplayName
),
QuestionLinkAndDuplicateStats AS (
    -- Analyze incoming and outgoing links/duplicates for questions, focusing on high-impact relations.
    SELECT
        pl.PostId AS QuestionId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedQuestionCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateQuestionCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 AND p_related.Score > 50 THEN 1 ELSE 0 END) AS HighScoreLinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 AND p_related.ViewCount > 10000 THEN 1 ELSE 0 END) AS HighViewDuplicateCount
    FROM PostLinks pl
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    WHERE pl.LinkTypeId IN (1, 3) -- Linked or Duplicate
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / (3600 * 24 * 365.25) AS UserAccountAgeYears, -- Account age in years
    COALESCE(u.Location, 'Earth') AS UserLocation,
    u.Views AS UserProfileViews,
    qae.QuestionId,
    qae.QuestionTitle,
    qae.QuestionScore,
    qae.QuestionViewCount,
    qae.QuestionCommentCount AS QuestionRootCommentCount,
    qae.AnswerCountActual,
    qae.AverageAnswerScore,
    COALESCE(qae.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
    CASE
        WHEN qae.QuestionScore >= 150 AND qae.AnswerCountActual >= 10 AND qae.AverageAnswerScore > 5 THEN 'Exceptional Question'
        WHEN qae.QuestionScore >= 50 OR qae.QuestionViewCount >= 25000 THEN 'High Impact Question'
        WHEN qae.QuestionScore > 0 OR qae.QuestionViewCount >= 1000 THEN 'Moderate Question'
        ELSE 'Low Impact Question'
    END AS QuestionImpactLevel,
    COALESCE(uphs.EditCount, 0) AS QuestionEditHistoryCount,
    COALESCE(uphs.CloseDeleteLockCount, 0) AS QuestionCloseDeleteLockHistoryCount,
    DATE_TRUNC('day', qae.QuestionCreationDate) AS QuestionCreationDay,
    rb.BadgeName AS HighestClassBadge,
    rb.BadgeClass AS HighestClassBadgeClass,
    urs.LatestPostTitle,
    urs.LatestCommentText,
    COALESCE(qls.LinkedQuestionCount, 0) AS LinkedQuestionsToThisPost,
    COALESCE(qls.DuplicateQuestionCount, 0) AS DuplicatedQuestionsToThisPost,
    COALESCE(qls.HighScoreLinkedCount, 0) AS HighScoreLinkedQuestions,
    COALESCE(qls.HighViewDuplicateCount, 0) AS HighViewDuplicateSources,
    -- Calculate a weighted composite score for questions
    (qae.QuestionScore * 0.4 + qae.ViewCount * 0.001 + qae.AnswerCountActual * 2 + qae.TotalCommentsOnQuestion * 0.5 + COALESCE(qae.AverageAnswerScore, 0) * 1.5) AS QuestionEngagementCompositeScore,
    RANK() OVER (PARTITION BY DATE_TRUNC('quarter', u.CreationDate) ORDER BY u.Reputation DESC, u.Views DESC) AS UserReputationRankByQuarter,
    NTILE(10) OVER (ORDER BY (qae.QuestionScore + COALESCE(qae.AverageAnswerScore,0)) DESC, qae.QuestionViewCount DESC) AS QuestionPerformanceDecile,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC, qae.QuestionScore DESC, COALESCE(uphs.EditCount, 0) DESC, qae.QuestionCreationDate DESC) AS OverallUserQuestionRank
FROM Users u
INNER JOIN QuestionAnswerEngagement qae ON u.Id = qae.OwnerUserId
LEFT JOIN UserPostHistorySummary uphs ON u.Id = uphs.UserId AND qae.QuestionId = uphs.PostId
LEFT JOIN UserBadgeRank rb ON u.Id = rb.UserId AND rb.rn = 1
LEFT JOIN UserRecentActivitySummary urs ON u.Id = urs.UserId
LEFT JOIN QuestionLinkAndDuplicateStats qls ON qae.QuestionId = qls.QuestionId
WHERE
    u.Reputation >= 1000 -- Filter for active, established users
    AND qae.QuestionCreationDate BETWEEN '2020-01-01' AND '2023-12-31' -- Specific time window for questions
    AND (qae.QuestionScore > 50 OR qae.QuestionViewCount > 10000) -- Significant questions only
    AND (qae.QuestionTitle IS NOT NULL AND LENGTH(qae.QuestionTitle) > 10 AND qae.QuestionTitle LIKE '%SQL%' AND qae.QuestionTitle NOT ILIKE '%beginner%') -- Complex string predicates
    AND (
        qae.QuestionTags LIKE '%<sql>%' OR
        qae.QuestionTags LIKE '%<database>%' OR
        qae.QuestionTags LIKE '%<performance>%'
    ) -- Specific tag filtering
    AND (qae.AverageAnswerScore IS NOT NULL AND qae.AverageAnswerScore > 0) -- Ensure answers exist and are scored positively
    AND NOT EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = qae.QuestionId
          AND v.VoteTypeId = 4 -- Exclude questions marked as offensive
          AND v.CreationDate > qae.QuestionCreationDate
    )
    -- Additional NULL logic and combined conditions
    AND (u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NOT NULL) -- User has provided some personal info
    AND (uphs.EditCount > 0 OR qls.LinkedQuestionCount > 0) -- Question has been edited or linked
ORDER BY
    OverallUserQuestionRank ASC,
    QuestionEngagementCompositeScore DESC,
    QuestionCreationDate DESC
LIMIT 500;
