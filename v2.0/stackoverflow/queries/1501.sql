-- {"query": "1501.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2496}
WITH UserPostHistorySummary AS (
    SELECT
        ph.UserId,
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) THEN 1 END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 12, 14) THEN 1 END) AS CloseDeleteLockCount,
        MAX(ph.CreationDate) AS LastHistoryActivityDate
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.PostHistoryTypeId BETWEEN 1 AND 100
    GROUP BY ph.UserId, ph.PostId
),
QuestionAnswerEngagement AS (
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
        COALESCE(p_q.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        SUM(CASE WHEN p_a.Id IS NOT NULL THEN p_a.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT p_a.Id) AS AnswerCountActual,
        AVG(CASE WHEN p_a.Id IS NOT NULL THEN p_a.Score * 1.0 ELSE NULL END) AS AverageAnswerScore,
        MAX(p_a.CreationDate) AS LastAnswerDate,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(DISTINCT c.Id) AS TotalCommentsOnQuestion
    FROM Posts p_q
    LEFT JOIN Posts p_a ON p_q.Id = p_a.ParentId AND p_a.PostTypeId = 2
    LEFT JOIN Comments c ON p_q.Id = c.PostId
    WHERE p_q.PostTypeId = 1
      AND p_q.CreationDate >= TIMESTAMP '2018-01-01'
    GROUP BY
        p_q.Id, p_q.OwnerUserId, p_q.Score, p_q.ViewCount, p_q.CommentCount,
        p_q.CreationDate, p_q.LastActivityDate, p_q.Title, p_q.Tags, p_q.AcceptedAnswerId
),
UserBadgeRank AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class AS BadgeClass,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Class ASC, b.Date DESC) AS rn
    FROM Badges b
    WHERE b.Class IN (1, 2, 3)
),
UserRecentActivitySummary AS (
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
    SELECT
        pl.PostId AS QuestionId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedQuestionCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateQuestionCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 AND p_related.Score > 50 THEN 1 ELSE 0 END) AS HighScoreLinkedCount,
        SUM(CASE WHEN pl.LinkTypeId = 3 AND p_related.ViewCount > 10000 THEN 1 ELSE 0 END) AS HighViewDuplicateCount
    FROM PostLinks pl
    JOIN Posts p_related ON pl.RelatedPostId = p_related.Id
    WHERE pl.LinkTypeId IN (1, 3)
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    EXTRACT(EPOCH FROM (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - u.CreationDate)) / (3600 * 24 * 365.25) AS UserAccountAgeYears,
    COALESCE(u.Location, 'Earth') AS UserLocation,
    u.Views AS UserProfileViews,
    qae.QuestionId,
    qae.QuestionTitle,
    qae.QuestionScore,
    qae.QuestionViewCount,
    qae.QuestionCommentCount AS QuestionRootCommentCount,
    qae.AnswerCountActual,
    qae.AverageAnswerScore,
    CASE WHEN qae.AcceptedAnswerId = -1 THEN 0 ELSE 1 END AS HasAcceptedAnswer,
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
    (qae.QuestionScore * 0.4 + qae.QuestionViewCount * 0.001 + qae.AnswerCountActual * 2 + qae.TotalCommentsOnQuestion * 0.5 + COALESCE(qae.AverageAnswerScore, 0) * 1.5) AS QuestionEngagementCompositeScore,
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
    u.Reputation >= 1000
    AND qae.QuestionCreationDate BETWEEN DATE '2020-01-01' AND DATE '2023-12-31'
    AND (qae.QuestionScore > 50 OR qae.QuestionViewCount > 10000)
    AND (qae.QuestionTitle IS NOT NULL AND LENGTH(qae.QuestionTitle) > 10 AND qae.QuestionTitle LIKE '%SQL%' AND qae.QuestionTitle NOT ILIKE '%beginner%')
    AND (
        qae.QuestionTags LIKE '%<sql>%' OR
        qae.QuestionTags LIKE '%<database>%' OR
        qae.QuestionTags LIKE '%<performance>%'
    )
    AND (qae.AverageAnswerScore IS NOT NULL AND qae.AverageAnswerScore > 0)
    AND NOT EXISTS (
        SELECT 1
        FROM Votes v
        WHERE v.PostId = qae.QuestionId
          AND v.VoteTypeId = 4
          AND v.CreationDate > qae.QuestionCreationDate
    )
    AND (u.AboutMe IS NOT NULL OR u.WebsiteUrl IS NOT NULL)
    AND (COALESCE(uphs.EditCount, 0) > 0 OR COALESCE(qls.LinkedQuestionCount, 0) > 0)
ORDER BY
    OverallUserQuestionRank ASC,
    QuestionEngagementCompositeScore DESC,
    qae.QuestionCreationDate DESC
LIMIT 500;