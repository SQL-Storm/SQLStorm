-- {"query": "46016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2059}

WITH UserEngagementMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as QuestionCount,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgQuestionScore,
        AVG(a.Score) as AvgAnswerScore,
        EXTRACT(EPOCH FROM (MAX(u.LastAccessDate) - u.CreationDate))/86400 as DaysActive
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
        t.Count as TagUsageCount,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        AVG(p.AnswerCount) as AvgAnswers,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswer,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%' AND p.PostTypeId = 1
    WHERE t.Count > 100
    GROUP BY t.TagName, t.Count
),
AnswerQualityMetrics AS (
    SELECT 
        a.Id as AnswerId,
        a.OwnerUserId,
        a.ParentId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        q.CreationDate as QuestionDate,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END as IsAccepted,
        COUNT(DISTINCT c.Id) as AnswerComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as UpVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as DownVotes
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
        COUNT(*) as TotalEdits,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) as ContentEdits,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (7,8,9)) as Rollbacks,
        MIN(ph.CreationDate) as FirstEdit,
        MAX(ph.CreationDate) as LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.PostId
    HAVING COUNT(*) >= 3
),
NetworkAnalysis AS (
    SELECT 
        pl.PostId as SourcePost,
        pl.RelatedPostId as TargetPost,
        pl.LinkTypeId,
        lt.Name as LinkType,
        COUNT(*) OVER (PARTITION BY pl.PostId) as OutboundLinks,
        COUNT(*) OVER (PARTITION BY pl.RelatedPostId) as InboundLinks
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.CreationDate >= TIMESTAMP '2018-01-01'
)
SELECT 
    uem.DisplayName,
    uem.Reputation,
    uem.QuestionCount,
    uem.AnswerCount,
    uem.CommentCount,
    uem.BadgeCount,
    ROUND(uem.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ROUND(uem.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    ROUND(uem.DaysActive::numeric, 2) as DaysActive,
    COUNT(DISTINCT aqm.AnswerId) as HighQualityAnswers,
    AVG(aqm.AnswerScore) as AvgHighQualityAnswerScore,
    AVG(aqm.HoursToAnswer) as AvgResponseTime,
    SUM(aqm.IsAccepted) as AcceptedAnswersCount,
    COUNT(DISTINCT ep.PostId) as EditedPosts,
    AVG(ep.TotalEdits) as AvgEditsPerPost,
    STRING_AGG(DISTINCT ttp.TagName, ', ' ORDER BY ttp.AvgScore DESC) FILTER (WHERE ttp.AvgScore > 10) as TopPerformingTags,
    COUNT(DISTINCT na.SourcePost) as PostsWithOutboundLinks,
    AVG(na.OutboundLinks) as AvgOutboundLinks
FROM UserEngagementMetrics uem
LEFT JOIN AnswerQualityMetrics aqm ON uem.Id = aqm.OwnerUserId AND aqm.AnswerScore >= 5
LEFT JOIN EditingPatterns ep ON ep.PostId IN (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uem.Id OR p.LastEditorUserId = uem.Id
)
LEFT JOIN Posts p ON p.OwnerUserId = uem.Id AND p.PostTypeId = 1
LEFT JOIN TopTagPerformance ttp ON ttp.QuestionCount > 50 AND p.Tags LIKE '%<' || ttp.TagName || '>%'
LEFT JOIN NetworkAnalysis na ON na.SourcePost IN (SELECT Id FROM Posts WHERE OwnerUserId = uem.Id)
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
