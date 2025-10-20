-- {"query": "46007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 16058, "output_tokens": 12757} 

WITH RECURSIVE UserInfluence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as TotalUpvotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as TotalDownvotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT b.Id) as BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5
),
QuestionMetrics AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.OwnerUserId,
        q.CreationDate,
        STRING_TO_ARRAY(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><') as TagArray,
        COUNT(DISTINCT a.Id) as ActualAnswers,
        MAX(a.Score) as BestAnswerScore,
        AVG(a.Score) as AvgAnswerScore,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT pl.Id) as LinkedPosts,
        CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END as HasAcceptedAnswer
    FROM Posts q
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON q.Id = c.PostId OR a.Id = c.PostId
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId
    WHERE q.PostTypeId = 1 
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '18 months'
        AND q.Score >= 5
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, 
             q.FavoriteCount, q.OwnerUserId, q.CreationDate, q.Tags, q.AcceptedAnswerId
),
TagEngagement AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        COUNT(DISTINCT qm.QuestionId) as RecentQuestions,
        AVG(qm.QuestionScore) as AvgQuestionScore,
        AVG(qm.ViewCount) as AvgViews,
        AVG(qm.AnswerCount) as AvgAnswers,
        SUM(qm.TotalComments) as TotalEngagement,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qm.QuestionScore) as MedianScore
    FROM Tags t
    CROSS JOIN LATERAL (
        SELECT * FROM QuestionMetrics qm 
        WHERE t.TagName = ANY(qm.TagArray)
    ) qm
    GROUP BY t.Id, t.TagName, t.Count
    HAVING COUNT(DISTINCT qm.QuestionId) >= 10
),
UserTagExpertise AS (
    SELECT 
        ui.Id as UserId,
        ui.DisplayName,
        te.TagName,
        COUNT(DISTINCT qm.QuestionId) as QuestionsInTag,
        SUM(qm.QuestionScore) as TotalScoreInTag,
        AVG(qm.BestAnswerScore) as AvgBestAnswer,
        RANK() OVER (PARTITION BY te.TagName ORDER BY SUM(qm.QuestionScore) DESC) as TagRank
    FROM UserInfluence ui
    JOIN QuestionMetrics qm ON ui.Id = qm.OwnerUserId
    CROSS JOIN LATERAL UNNEST(qm.TagArray) as tag
    JOIN TagEngagement te ON tag = te.TagName
    GROUP BY ui.Id, ui.DisplayName, te.TagName
),
PostEditActivity AS (
    SELECT 
        ph.PostId,
        COUNT(DISTINCT ph.UserId) as UniqueEditors,
        COUNT(*) as TotalEdits,
        MAX(ph.CreationDate) - MIN(ph.CreationDate) as EditTimespan,
        STRING_AGG(DISTINCT pht.Name, ', ') as EditTypes
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 24)
    GROUP BY ph.PostId
    HAVING COUNT(*) >= 3
),
ComplexMetrics AS (
    SELECT 
        qm.QuestionId,
        qm.Title,
        qm.QuestionScore,
        qm.ViewCount,
        ui.DisplayName as AuthorName,
        ui.Reputation as AuthorReputation,
        ui.TotalUpvotes as AuthorTotalUpvotes,
        qm.ActualAnswers,
        qm.BestAnswerScore,
        qm.HasAcceptedAnswer,
        COALESCE(pea.TotalEdits, 0) as EditCount,
        COALESCE(pea.UniqueEditors, 0) as EditorCount,
        qm.TagArray,
        ARRAY_AGG(DISTINCT ute.TagName) FILTER (WHERE ute.TagRank <= 3) as TopTags,
        AVG(te.AvgQuestionScore) as TagsAvgScore,
        (qm.QuestionScore * 1.0 / NULLIF(qm.ViewCount, 0)) * 10000 as EngagementRatio,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - qm.CreationDate))/86400 as DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM qm.CreationDate), EXTRACT(MONTH FROM qm.CreationDate) 
                          ORDER BY qm.QuestionScore DESC, qm.ViewCount DESC) as MonthlyRank
    FROM QuestionMetrics qm
    JOIN UserInfluence ui ON qm.OwnerUserId = ui.Id
    LEFT JOIN PostEditActivity pea ON qm.QuestionId = pea.PostId
    LEFT JOIN LATERAL UNNEST(qm.TagArray) as tag ON true
    LEFT JOIN TagEngagement te ON tag = te.TagName
    LEFT JOIN UserTagExpertise ute ON ui.Id = ute.UserId AND tag = ute.TagName
    GROUP BY qm.QuestionId, qm.Title, qm.QuestionScore, qm.ViewCount, ui.DisplayName, 
             ui.Reputation, ui.TotalUpvotes, qm.ActualAnswers, qm.BestAnswerScore, 
             qm.HasAcceptedAnswer, pea.TotalEdits, pea.UniqueEditors, qm.TagArray, 
             qm.CreationDate
)
SELECT 
    cm.QuestionId,
    cm.Title,
    cm.AuthorName,
    cm.AuthorReputation,
    cm.QuestionScore,
    cm.ViewCount,
    cm.ActualAnswers,
    cm.BestAnswerScore,
    cm.EditCount,
    cm.EditorCount,
    cm.TopTags,
    ROUND(cm.TagsAvgScore::numeric, 2) as AvgTagScore,
    ROUND(cm.EngagementRatio::numeric, 4) as EngagementRatio,
    ROUND(cm.DaysSinceCreation::numeric, 1) as DaysSinceCreation,
    cm.MonthlyRank,
    NTILE(10) OVER (ORDER BY cm.QuestionScore) as ScoreDecile,
    PERCENT_RANK() OVER (ORDER BY cm.ViewCount) as ViewPercentile
FROM ComplexMetrics cm
WHERE cm.MonthlyRank <= 50
    AND cm.TagsAvgScore > 10
ORDER BY cm.QuestionScore DESC, cm.ViewCount DESC, cm.EngagementRatio DESC
LIMIT 100;
