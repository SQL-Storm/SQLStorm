-- {"query": "2391.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1138}
WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(b.Date) DESC NULLS LAST) AS RecentBadgeRank
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
        COUNT(CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        AVG(CASE WHEN p.PostTypeId IN (1, 2) THEN p.Score END) AS AvgPostScore,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) AS TotalQuestionViews
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
        MAX(CASE WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER) ELSE NULL END) AS CloseReasonId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.PostId
),
RecentCommentsOnPosts AS (
    SELECT
        c.PostId,
        c.Text AS LatestComment,
        c.CreationDate AS LatestCommentDate
    FROM (
      SELECT
        c.*,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) rn
      FROM Comments c
    ) c
    WHERE c.rn = 1
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
    ROUND(COALESCE(qag.AvgPostScore, 0), 2) AS AvgPostScore,
    COALESCE(qag.TotalQuestionViews, 0) AS TotalQuestionViews,
    p.Id AS QuestionId,
    p.Title,
    COALESCE(pls.LinkedCount, 0) AS TimesLinked,
    COALESCE(pls.DuplicateCount, 0) AS DuplicateCount,
    qci.FirstCloseDate,
    crt.Name AS CloseReason,
    rc.LatestComment,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) / 86400 AS DaysSinceAsked,
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
    (p.Score > 5 AND COALESCE(qci.FirstCloseDate, CAST('2024-10-01 12:34:56' AS timestamp)) > p.CreationDate + INTERVAL '30 days')
    OR p.Id IS NULL
)
GROUP BY
    u.DisplayName,
    ba.GoldBadges,
    ba.SilverBadges,
    ba.BronzeBadges,
    ba.BadgeScore,
    qag.QuestionCount,
    qag.AnswerCount,
    qag.AvgPostScore,
    qag.TotalQuestionViews,
    p.Id,
    p.Title,
    pls.LinkedCount,
    pls.DuplicateCount,
    qci.FirstCloseDate,
    crt.Name,
    rc.LatestComment,
    p.CreationDate,
    ans.AnswerId,
    ans.Score,
    ans.AnswerRank,
    p.AcceptedAnswerId,
    u.Location,
    u.WebsiteUrl,
    u.AboutMe,
    u.Reputation,
    u.Id
ORDER BY ba.BadgeScore DESC, u.Reputation DESC, p.CreationDate DESC
LIMIT 100;