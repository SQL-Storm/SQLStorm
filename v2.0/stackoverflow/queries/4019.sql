-- {"query": "4019.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1136}
WITH RankedAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererId,
        u.DisplayName AS AnswererDisplayName,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 2 AND p.Score >= 0
),
UserAnswerStats AS (
    SELECT
        ra.AnswererId,
        COUNT(ra.AnswerId) AS TotalAnswers,
        AVG(ra.AnswerScore) AS AvgAnswerScore,
        SUM(CASE WHEN ra.rn = 1 THEN 1 ELSE 0 END) AS AcceptedAnswerCount
    FROM RankedAnswers ra
    GROUP BY ra.AnswererId
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerId,
        q.Title AS QuestionTitle,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.AnswerCount AS QuestionAnswerCount,
        q.FavoriteCount AS QuestionFavoriteCount,
        q.ClosedDate,
        q.ViewCount,
        CASE WHEN q.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COALESCE(u.DisplayName, q.OwnerDisplayName) AS QuestionOwnerDisplayName,
        COALESCE(u.Reputation, 0) AS QuestionOwnerReputation,
        pt.Name AS PostTypeName
    FROM Posts q
    LEFT JOIN Users u ON q.OwnerUserId = u.Id
    JOIN PostTypes pt ON q.PostTypeId = pt.Id
    WHERE q.PostTypeId = 1
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(CASE WHEN c.UserId IS NULL THEN 1 END) AS AnonymousComments
    FROM Comments c
    GROUP BY c.PostId
)
SELECT
    qd.QuestionId,
    qd.QuestionTitle,
    qd.QuestionOwnerDisplayName,
    qd.QuestionOwnerReputation,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.QuestionAnswerCount,
    qd.QuestionFavoriteCount,
    qd.ViewCount,
    qd.IsClosed,
    CASE WHEN qd.ClosedDate IS NOT NULL THEN
        -- Format as YYYY-MM using standard SQL string functions
        CAST(EXTRACT(YEAR FROM qd.ClosedDate) AS VARCHAR) || '-' ||
        LPAD(CAST(EXTRACT(MONTH FROM qd.ClosedDate) AS VARCHAR), 2, '0')
    ELSE
        'N/A'
    END AS CloseMonth,
    COALESCE(ua.TotalAnswers, 0) AS TotalAnswersByOwner,
    COALESCE(ua.AvgAnswerScore, 0.0) AS AvgAnswerScoreByOwner,
    COALESCE(ua.AcceptedAnswerCount, 0) AS AcceptedAnswersByOwner,
    ca.TotalComments AS QuestionComments,
    ca.TotalCommentScore AS QuestionCommentScore,
    COALESCE(ra.AnswerId, -1) AS BestAnswerId,
    COALESCE(ra.AnswererDisplayName, 'No Accepted Answer') AS BestAnswererDisplayName,
    COALESCE(ra.AnswerScore, 0) AS BestAnswerScore,
    COALESCE(ra.AnswerCreationDate, TIMESTAMP '1970-01-01 00:00:00') AS BestAnswerCreationDate,
    (qd.QuestionScore * 1.0 / NULLIF(qd.ViewCount, 0)) AS ScoreToViewRatio,
    LENGTH(qd.QuestionTitle) AS TitleLength,
    SUBSTRING(qd.QuestionTitle FROM 1 FOR 5) AS FirstFiveCharsOfTitle,
    CASE
        WHEN qd.QuestionOwnerReputation > 10000 THEN 'High Reputation'
        WHEN qd.QuestionOwnerReputation BETWEEN 1000 AND 10000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationCategory,
    ph.HistoryCount AS PostHistoryCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = qd.QuestionId OR pl.RelatedPostId = qd.QuestionId) AS RelatedPostLinks
FROM QuestionDetails qd
LEFT JOIN UserAnswerStats ua ON qd.QuestionOwnerId = ua.AnswererId
LEFT JOIN RankedAnswers ra ON qd.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN CommentAggregates ca ON qd.QuestionId = ca.PostId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS HistoryCount
    FROM PostHistory
    GROUP BY PostId
) ph ON qd.QuestionId = ph.PostId
WHERE qd.QuestionScore > 10
GROUP BY
    qd.QuestionId,
    qd.QuestionTitle,
    qd.QuestionOwnerDisplayName,
    qd.QuestionOwnerReputation,
    qd.QuestionCreationDate,
    qd.QuestionScore,
    qd.QuestionAnswerCount,
    qd.QuestionFavoriteCount,
    qd.ViewCount,
    qd.IsClosed,
    qd.ClosedDate,
    ua.TotalAnswers,
    ua.AvgAnswerScore,
    ua.AcceptedAnswerCount,
    ca.TotalComments,
    ca.TotalCommentScore,
    ra.AnswerId,
    ra.AnswererDisplayName,
    ra.AnswerScore,
    ra.AnswerCreationDate,
    ph.HistoryCount
ORDER BY qd.QuestionCreationDate DESC
LIMIT 100;