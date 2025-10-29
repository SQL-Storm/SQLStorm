-- {"query": "4800.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1206} 

WITH RecentQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title AS QuestionTitle,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-1 year')
),
TopAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(p.Id) AS AnswerCount,
        SUM(p.Score) AS TotalAnswerScore,
        AVG(p.Score) AS AverageAnswerScore,
        MAX(p.CreationDate) AS LastAnswerDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY COUNT(p.Id) DESC, SUM(p.Score) DESC) AS ans_rn
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
UserEngagement AS (
    SELECT
        UserId,
        COUNT(Id) AS CommentCount,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveCommentCount,
        AVG(Score) AS AverageCommentScore,
        MAX(CreationDate) AS LastCommentDate
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
QuestionMetrics AS (
    SELECT
        rq.QuestionId,
        rq.QuestionTitle,
        rq.OwnerUserId,
        rq.QuestionCreationDate,
        rq.QuestionScore,
        rq.OwnerDisplayName,
        rq.OwnerReputation,
        COALESCE(ta.AnswerCount, 0) AS ActualAnswerCount,
        COALESCE(ta.TotalAnswerScore, 0) AS TotalAnswerScore,
        COALESCE(ta.AverageAnswerScore, 0.0) AS AverageAnswerScore,
        ta.LastAnswerDate,
        ue.CommentCount AS OwnerCommentCount,
        ue.PositiveCommentCount AS OwnerPositiveCommentCount,
        ue.AverageCommentScore AS OwnerAverageCommentScore,
        ue.LastCommentDate AS OwnerLastCommentDate,
        CASE
            WHEN rq.QuestionScore > 100 THEN 'High Score'
            WHEN rq.QuestionScore > 0 THEN 'Positive Score'
            WHEN rq.QuestionScore = 0 THEN 'Zero Score'
            ELSE 'Negative Score'
        END AS ScoreCategory,
        CASE
            WHEN rq.OwnerReputation >= 50000 THEN 'Expert'
            WHEN rq.OwnerReputation >= 10000 THEN 'Experienced'
            WHEN rq.OwnerReputation >= 1000 THEN 'Intermediate'
            ELSE 'Novice'
        END AS ReputationTier,
        DATEDIFF(CURRENT_TIMESTAMP, rq.QuestionCreationDate) AS DaysSinceCreation,
        IIF(rq.OwnerUserId IS NULL OR EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = rq.OwnerUserId AND b.Name LIKE '%Guru%'), 'Community or Guru', 'Regular User') AS UserBadgeStatus
    FROM RecentQuestions rq
    LEFT JOIN TopAnswers ta ON rq.QuestionId = ta.QuestionId
    LEFT JOIN UserEngagement ue ON rq.OwnerUserId = ue.UserId
    WHERE rq.rn <= 100
)
SELECT
    qm.QuestionId,
    qm.QuestionTitle,
    qm.OwnerDisplayName,
    qm.OwnerReputation,
    qm.QuestionScore,
    qm.ActualAnswerCount,
    qm.TotalAnswerScore,
    qm.AverageAnswerScore,
    qm.DaysSinceCreation,
    qm.ScoreCategory,
    qm.ReputationTier,
    qm.UserBadgeStatus,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = qm.QuestionId AND c.Score < 0) AS NegativeCommentCount,
    CASE
        WHEN qm.LastAnswerDate IS NOT NULL AND qm.QuestionCreationDate IS NOT NULL THEN
            STRFTIME('%Y-%m-%d %H:%M:%S', qm.LastAnswerDate)
        ELSE
            'N/A'
    END AS FormattedLastAnswerDate,
    CASE
        WHEN qm.OwnerLastCommentDate IS NOT NULL AND qm.QuestionCreationDate IS NOT NULL THEN
            STRFTIME('%Y-%m-%d %H:%M:%S', qm.OwnerLastCommentDate)
        ELSE
            'N/A'
    END AS FormattedOwnerLastCommentDate,
    '---' || UPPER(SUBSTR(qm.QuestionTitle, 1, 3)) || SUBSTR('000000', 1, 6 - LENGTH(qm.QuestionScore)) || qm.QuestionScore AS TitleScoreIdentifier
FROM QuestionMetrics qm
WHERE qm.OwnerReputation > 1000
ORDER BY qm.QuestionScore DESC, qm.ActualAnswerCount DESC
LIMIT 50;
