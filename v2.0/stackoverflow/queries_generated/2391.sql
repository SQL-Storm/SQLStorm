-- {"query": "2391.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1138} 
WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC NULLS LAST) AS RecentBadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopUsersByBadgeScore AS (
    SELECT
        UserId,
        DisplayName,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        (GoldBadges * 3 + SilverBadges * 2 + BronzeBadges) AS BadgeScore
    FROM UserBadgeCounts
    WHERE RecentBadgeRank <= 5
),
QuestionAnswerAggregates AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgPostScore,
        SUM(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
PostLinkStats AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateCount
    FROM PostLinks pl
    GROUP BY pl.PostId
),
QuestionCloseInfo AS (
    SELECT
        ph.PostId,
        MIN(ph.CreationDate) AS FirstCloseDate,
        MAX(CAST(ph.Comment AS INT)) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
RecentCommentsOnPosts AS (
    SELECT DISTINCT ON (c.PostId)
        c.PostId,
        c.Text AS LatestComment,
        c.CreationDate AS LatestCommentDate
    FROM Comments c
    ORDER BY c.PostId, c.CreationDate DESC
),
AnswerRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
)
SELECT
    u.DisplayName,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.BadgeScore,
    COALESCE(qag.QuestionCount, 0) AS QuestionsPosted,
    COALESCE(qag.AnswerCount, 0) AS AnswersPosted,
    ROUND(COALESCE(qag.AvgPostScore, 0)::numeric, 2) AS AvgPostScore,
    COALESCE(qag.TotalQuestionViews, 0) AS TotalQuestionViews,
    p.Id AS QuestionId,
    p.Title,
    COALESCE(pls.LinkedCount, 0) AS TimesLinked,
    COALESCE(pls.DuplicateCount, 0) AS DuplicateCount,
    qci.FirstCloseDate,
    crt.Name AS CloseReason,
    rc.LatestComment,
    EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400 AS DaysSinceAsked,
    ans.AnswerId,
    ans.Score AS AnswerScore,
    ans.AnswerRank,
    CASE
        WHEN ans.AnswerId = p.AcceptedAnswerId THEN 'Accepted'
        WHEN ans.AnswerRank = 1 THEN 'TopScoreUnaccepted'
        ELSE 'Other'
    END AS AnswerStatus,
    CONCAT_WS(' / ', 
        COALESCE(u.Location, 'Unknown'), 
        COALESCE(NULLIF(u.WebsiteUrl, ''), 'No Website'),
        COALESCE(NULLIF(u.AboutMe, ''), 'No AboutMe')
    ) AS UserInfoSummary
FROM TopUsersByBadgeScore ba
INNER JOIN Users u ON u.Id = ba.UserId
LEFT JOIN QuestionAnswerAggregates qag ON qag.OwnerUserId = u.Id
LEFT JOIN Posts p ON p.PostTypeId = 1 AND p.OwnerUserId = u.Id
LEFT JOIN PostLinkStats pls ON pls.PostId = p.Id
LEFT JOIN QuestionCloseInfo qci ON qci.PostId = p.Id
LEFT JOIN CloseReasonTypes crt ON crt.Id = qci.CloseReasonId
LEFT JOIN RecentCommentsOnPosts rc ON rc.PostId = p.Id
LEFT JOIN AnswerRanks ans ON ans.QuestionId = p.Id
WHERE ba.BadgeScore > 0
AND (
    (p.Score > 5 AND COALESCE(qci.FirstCloseDate, NOW()) > p.CreationDate + INTERVAL '30 days')
    OR p.Id IS NULL
)
ORDER BY ba.BadgeScore DESC, u.Reputation DESC, p.CreationDate DESC
LIMIT 100;