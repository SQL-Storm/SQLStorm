SELECT
    u.Id AS UserID,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalQuestions,
    COUNT(DISTINCT a.Id) AS TotalAnswers,
    AVG(p.Score) AS AvgQuestionScore,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(p.CreationDate) AS LastQuestionDate,
    MAX(a.CreationDate) AS LastAnswerDate,
    COUNT(DISTINCT c.Id) AS TotalComments,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotesReceived,
    COUNT(DISTINCT p.Id) FILTER (WHERE (p.Tags IS NOT NULL AND EXISTS (
        SELECT 1 FROM UNNEST(CAST(p.Tags AS text[])) AS t WHERE t = 'performance'
    )) OR p.Title ILIKE '%benchmark%') AS PerformanceRelatedQuestions,
    COUNT(DISTINCT a.Id) FILTER (WHERE a.Title ILIKE '%optimization%') AS OptimizationAnswers,
    (SELECT COUNT(*) FROM PostLinks pl WHERE (pl.PostId = p.Id OR pl.PostId = a.Id OR (p.Id IS NULL AND pl.PostId = a.Id) OR (a.Id IS NULL AND pl.PostId = p.Id)) AND pl.LinkTypeId = 3) AS TotalDuplicatesLinked,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 24) AS TotalSuggestedEdits
FROM Users u
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
LEFT JOIN Comments c ON c.UserId = u.Id
LEFT JOIN Badges b ON b.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
GROUP BY u.Id, u.DisplayName, p.Id, a.Id, p.Tags, p.Title, a.Title, p.Score, a.Score, p.CreationDate, a.CreationDate
ORDER BY TotalQuestions DESC, TotalAnswers DESC
LIMIT 100;