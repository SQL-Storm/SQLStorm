-- {"query": "4392.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1134}
WITH QuestionMetrics AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        u.DisplayName AS OwnerDisplayName,
        p.OwnerUserId AS OwnerUserId,
        p.Score AS QuestionScore,
        p.ViewCount AS QuestionViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnQuestion,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
AnswerMetrics AS (
    SELECT
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS AnswerCountByAnswers,
        SUM(a.Score) AS TotalAnswerScore,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.CreationDate) AS LatestAnswerDate,
        COUNT(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 END) AS IsAcceptedAnswerPresent
    FROM Posts a
    JOIN Posts p ON p.Id = a.ParentId
    WHERE a.PostTypeId = 2 AND a.ParentId IS NOT NULL
    GROUP BY a.ParentId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        COUNT(DISTINCT ph.PostId) AS PostHistoryEdits
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    GROUP BY u.Id, u.DisplayName
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Name = 'Duplicate' THEN pl.Id END) AS DuplicateLinksToOthers,
        COUNT(CASE WHEN lt.Name = 'Linked' THEN pl.Id END) AS LinkedToOthers
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    qm.Title AS QuestionTitle,
    qm.OwnerDisplayName,
    qm.QuestionCreationDate,
    qm.QuestionScore,
    qm.QuestionViewCount,
    qm.AnswerCount AS PostAnswerCount,
    COALESCE(am.AnswerCountByAnswers, 0) AS AnswerCountViaJoin,
    COALESCE(am.TotalAnswerScore, 0) AS TotalAnswerScore,
    am.AvgAnswerScore,
    qm.FavoriteCount,
    qm.CommentCountOnQuestion,
    CAST(
      EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - CAST(qm.QuestionCreationDate AS TIMESTAMP)))/86400
      AS INTEGER
    ) AS DaysSinceCreation,
    CASE
        WHEN qm.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN qm.AnswerCount = 0 THEN 'Unanswered'
        ELSE 'Active'
    END AS QuestionStatus,
    (COALESCE(ue.GoldBadges,0) || 'G/' || COALESCE(ue.SilverBadges,0) || 'S/' || COALESCE(ue.BronzeBadges,0) || 'B') AS UserBadgeSummary,
    COALESCE(ue.TotalUpvotes,0) AS TotalUpvotes,
    COALESCE(ue.TotalDownvotes,0) AS TotalDownvotes,
    COALESCE(pl.DuplicateLinksToOthers,0) AS DuplicateLinksToOthers,
    COALESCE(pl.LinkedToOthers,0) AS LinkedToOthers,
    CASE WHEN qm.QuestionScore > 1000 AND qm.AnswerCount > 10 THEN 'High Impact' WHEN qm.QuestionScore < 0 THEN 'Negative Score' ELSE 'Standard' END AS ImpactCategory,
    (SELECT COUNT(*) FROM Posts ps WHERE ps.ParentId = qm.QuestionId AND ps.Score < 0) AS NegativeScoreAnswers
FROM QuestionMetrics qm
LEFT JOIN AnswerMetrics am ON qm.QuestionId = am.QuestionId
LEFT JOIN UserEngagement ue ON qm.OwnerUserId = ue.UserId
LEFT JOIN PostLinkAnalysis pl ON qm.QuestionId = pl.PostId
WHERE qm.RowNum <= 100
  AND qm.QuestionScore > -5
  AND (qm.ClosedDate IS NULL OR qm.ClosedDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '6 months'))
GROUP BY
  qm.Title,
  qm.OwnerDisplayName,
  qm.QuestionCreationDate,
  qm.QuestionScore,
  qm.QuestionViewCount,
  qm.AnswerCount,
  am.AnswerCountByAnswers,
  am.TotalAnswerScore,
  am.AvgAnswerScore,
  qm.FavoriteCount,
  qm.CommentCountOnQuestion,
  qm.ClosedDate,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ue.TotalUpvotes,
  ue.TotalDownvotes,
  pl.DuplicateLinksToOthers,
  pl.LinkedToOthers,
  qm.QuestionId,
  qm.OwnerUserId,
  qm.RowNum
ORDER BY qm.QuestionCreationDate DESC;