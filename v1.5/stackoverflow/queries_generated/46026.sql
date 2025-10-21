-- {"query": "46026.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 59644, "output_tokens": 47922} 

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
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgQuestionScore,
        AVG(a.Score) as AvgAnswerScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= CURRENT_DATE - INTERVAL '3 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) > 5 OR COUNT(DISTINCT a.Id) > 10
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        AVG(p.Score) as AvgTagScore,
        AVG(p.ViewCount) as AvgTagViews,
        COUNT(DISTINCT p.OwnerUserId) as UniqueContributors,
        SUM(p.AnswerCount) as TotalAnswers,
        COUNT(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 END) as QuestionsWithAcceptedAnswer,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
    GROUP BY t.Id, t.TagName, t.Count
),
PostInteractionChains AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount as QuestionComments,
        u.DisplayName as QuestionAuthor,
        u.Reputation as AuthorReputation,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerDate,
        au.DisplayName as AnswerAuthor,
        au.Reputation as AnswerAuthorReputation,
        COUNT(DISTINCT ac.Id) as AnswerComments,
        COUNT(DISTINCT v.Id) as AnswerVotes,
        COUNT(DISTINCT ph.Id) as QuestionEditCount,
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))/3600 as HoursToAnswer,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) as AnswerRank
    FROM Posts q
    INNER JOIN Users u ON q.OwnerUserId = u.Id
    LEFT JOIN Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN Users au ON a.OwnerUserId = au.Id
    LEFT JOIN Comments ac ON a.Id = ac.PostId
    LEFT JOIN Votes v ON a.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE q.PostTypeId = 1
        AND q.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
        AND q.Score > 3
        AND q.ViewCount > 100
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount,
             u.DisplayName, u.Reputation, a.Id, a.Score, a.CreationDate, 
             au.DisplayName, au.Reputation
),
CrossMetricAnalysis AS (
    SELECT 
        uem.DisplayName,
        uem.Reputation,
        uem.QuestionCount,
        uem.AnswerCount,
        uem.BadgeCount,
        uem.AvgQuestionScore,
        uem.AvgAnswerScore,
        COALESCE(tag_stats.PreferredTag, 'None') as PreferredTag,
        COALESCE(tag_stats.TagQuestions, 0) as TagQuestions,
        COALESCE(interaction_stats.AvgAnswerTime, 0) as AvgAnswerTimeHours,
        COALESCE(interaction_stats.AcceptanceRate, 0) as AnswerAcceptanceRate,
        DENSE_RANK() OVER (ORDER BY uem.Reputation DESC) as ReputationRank,
        DENSE_RANK() OVER (ORDER BY uem.AnswerCount DESC) as AnswerRank,
        NTILE(10) OVER (ORDER BY uem.Reputation) as ReputationDecile
    FROM UserEngagementMetrics uem
    LEFT JOIN LATERAL (
        SELECT 
            tp.TagName as PreferredTag,
            COUNT(DISTINCT p.Id) as TagQuestions
        FROM Posts p
        INNER JOIN TagPopularity tp ON p.Tags LIKE '%<' || tp.TagName || '>%'
        WHERE p.OwnerUserId = uem.Id AND p.PostTypeId = 1
        GROUP BY tp.TagName
        ORDER BY COUNT(DISTINCT p.Id) DESC
        LIMIT 1
    ) tag_stats ON true
    LEFT JOIN LATERAL (
        SELECT 
            AVG(pic.HoursToAnswer) as AvgAnswerTime,
            COUNT(CASE WHEN pic.AnswerId = q.AcceptedAnswerId THEN 1 END)::float / 
                NULLIF(COUNT(DISTINCT pic.AnswerId), 0) as AcceptanceRate
        FROM PostInteractionChains pic
        INNER JOIN Posts q ON pic.QuestionId = q.Id
        WHERE pic.AnswerAuthor = uem.DisplayName
    ) interaction_stats ON true
)
SELECT 
    cma.DisplayName,
    cma.Reputation,
    cma.QuestionCount,
    cma.AnswerCount,
    cma.BadgeCount,
    ROUND(cma.AvgQuestionScore::numeric, 2) as AvgQuestionScore,
    ROUND(cma.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    cma.PreferredTag,
    cma.TagQuestions,
    ROUND(cma.AvgAnswerTimeHours::numeric, 2) as AvgAnswerTimeHours,
    ROUND((cma.AnswerAcceptanceRate * 100)::numeric, 2) as AcceptanceRatePct,
    cma.ReputationRank,
    cma.AnswerRank,
    cma.ReputationDecile,
    tp.AvgTagScore as PreferredTagAvgScore,
    tp.UniqueContributors as TagContributors,
    tp.PopularityRank as TagPopularityRank
FROM CrossMetricAnalysis cma
LEFT JOIN TagPopularity tp ON cma.PreferredTag = tp.TagName
WHERE cma.QuestionCount + cma.AnswerCount > 15
ORDER BY cma.Reputation DESC, cma.AnswerCount DESC
LIMIT 500;
