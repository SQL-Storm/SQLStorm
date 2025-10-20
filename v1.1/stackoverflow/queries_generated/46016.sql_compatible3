WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(a.Score) AS AvgAnswerScore,
        EXTRACT(EPOCH FROM (MAX(u.LastAccessDate) - u.CreationDate)) / 86400 AS DaysActive
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TopTagPerformance AS (
    SELECT 
        t.TagName,
        t.Count AS TagUsageCount,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        AVG(p.Score) AS AvgScore,
        AVG(p.ViewCount) AS AvgViews,
        AVG(p.AnswerCount) AS AvgAnswers,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%' AND p.PostTypeId = 1
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
),
AnswerQualityMetrics AS (
    SELECT 
        a.Id AS AnswerId,
        a.OwnerUserId,
        a.ParentId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerDate,
        q.CreationDate AS QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 3600 AS HoursToAnswer,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViews,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
        COUNT(DISTINCT c.Id) AS AnswerComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes
    FROM Posts a
    INNER JOIN Posts q ON a.ParentId = q.Id
    LEFT JOIN Comments c ON a.Id = c.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId
    WHERE a.PostTypeId = 2 
      AND a.CreationDate >= TIMESTAMP '2019-01-01'
      AND q.Score >= 5
    GROUP BY a.Id, a.OwnerUserId, a.ParentId, a.Score, a.CreationDate, q.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId
),
EditingPatterns AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS TotalEdits,
        COUNT(DISTINCT ph.UserId) AS UniqueEditors,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) AS ContentEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) AS Rollbacks,
        MIN(ph.CreationDate) AS FirstEdit,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
    HAVING COUNT(*) >= 3
),
NetworkAnalysis AS (
    SELECT 
        pl.PostId AS SourcePost,
        pl.RelatedPostId AS TargetPost,
        pl.LinkTypeId,
        lt.Name AS LinkType,
        COUNT(*) OVER (PARTITION BY pl.PostId) AS OutboundLinks,
        COUNT(*) OVER (PARTITION BY pl.RelatedPostId) AS InboundLinks
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.CreationDate >= TIMESTAMP '2018-01-01'
)
SELECT 
    uem.Id,
    uem.DisplayName,
    uem.Reputation,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.CommentCount,
    uem.BadgeCount,
    ROUND(CAST(uem.AvgQuestionScore AS DECIMAL), 2) AS AvgQuestionScore,
    ROUND(CAST(uem.AvgAnswerScore AS DECIMAL), 2) AS AvgAnswerScore,
    ROUND(CAST(uem.DaysActive AS DECIMAL), 2) AS DaysActive,
    COUNT(DISTINCT aqm.AnswerId) AS HighQualityAnswers,
    AVG(aqm.AnswerScore) AS AvgHighQualityAnswerScore,
    AVG(aqm.HoursToAnswer) AS AvgResponseTime,
    SUM(aqm.IsAccepted) AS AcceptedAnswersCount,
    COUNT(DISTINCT ep.PostId) AS EditedPosts,
    AVG(ep.TotalEdits) AS AvgEditsPerPost,
    -- STRING_AGG with FILTER is not supported everywhere; use conditional aggregation to build comma-separated list if available.
    STRING_AGG(ttp.TagName, ', ' ORDER BY ttp.AvgScore DESC) FILTER (WHERE ttp.AvgScore > 10) AS TopPerformingTags,
    COUNT(DISTINCT na.SourcePost) AS PostsWithOutboundLinks,
    AVG(na.OutboundLinks) AS AvgOutboundLinks
FROM UserEngagementMetrics uem
LEFT JOIN AnswerQualityMetrics aqm ON uem.Id = aqm.OwnerUserId AND aqm.AnswerScore >= 5
LEFT JOIN EditingPatterns ep ON ep.PostId IN (
    SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = uem.Id OR p2.LastEditorUserId = uem.Id
)
LEFT JOIN Posts p ON p.OwnerUserId = uem.Id AND p.PostTypeId = 1
LEFT JOIN TopTagPerformance ttp ON ttp.QuestionCount > 50 AND p.Tags LIKE '%' || '<' || ttp.TagName || '>' || '%'
LEFT JOIN NetworkAnalysis na ON na.SourcePost IN (SELECT p3.Id FROM Posts p3 WHERE p3.OwnerUserId = uem.Id)
WHERE uem.Reputation > 1000
GROUP BY 
    uem.Id,
    uem.DisplayName,
    uem.Reputation,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.CommentCount,
    uem.BadgeCount,
    uem.AvgQuestionScore,
    uem.AvgAnswerScore,
    uem.DaysActive
HAVING COUNT(DISTINCT aqm.AnswerId) > 3
ORDER BY 
    (uem.Reputation * 0.3 + 
     COALESCE(AVG(aqm.AnswerScore), 0) * 100 * 0.4 + 
     COALESCE(SUM(aqm.IsAccepted), 0) * 50 * 0.3) DESC
LIMIT 100;