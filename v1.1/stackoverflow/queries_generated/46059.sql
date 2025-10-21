-- {"query": "46059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 1888}

WITH RECURSIVE UserInfluence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) as QuestionCount,
        COUNT(DISTINCT a.Id) as AnswerCount,
        COALESCE(SUM(p.Score), 0) + COALESCE(SUM(a.Score), 0) as TotalScore,
        COUNT(DISTINCT b.Id) as BadgeCount,
        CASE WHEN COUNT(DISTINCT b.Id) > 0 
             THEN SUM(CASE WHEN b.Class = 1 THEN 3 WHEN b.Class = 2 THEN 2 ELSE 1 END)
             ELSE 0 END as WeightedBadgeScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING COUNT(DISTINCT p.Id) + COUNT(DISTINCT a.Id) > 5
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count as TagUsageCount,
        COUNT(DISTINCT p.Id) as PostCount,
        AVG(p.Score) as AvgScore,
        AVG(p.ViewCount) as AvgViews,
        COUNT(DISTINCT p.AcceptedAnswerId) as AcceptedAnswerCount,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) as TotalUpvotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) as TotalDownvotes
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.PostTypeId = 1 AND p.CreationDate >= TIMESTAMP '2019-01-01'
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT p.Id) >= 100
),
EngagementMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        u.DisplayName as AuthorName,
        ui.TotalScore as AuthorTotalScore,
        COUNT(DISTINCT c.Id) as CommentEngagement,
        COUNT(DISTINCT ph.Id) as EditCount,
        COUNT(DISTINCT pl.Id) as LinkCount,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600.0 as HoursActive,
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) ORDER BY p.Score DESC) as YearlyRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextPostScore
    FROM Posts p
    INNER JOIN UserInfluence ui ON p.OwnerUserId = ui.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1 
        AND p.CreationDate >= TIMESTAMP '2020-01-01'
        AND p.Score >= 5
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             u.DisplayName, ui.TotalScore, p.LastActivityDate, p.CreationDate, p.OwnerUserId
)
SELECT 
    em.PostId,
    em.Title,
    em.AuthorName,
    em.Score,
    em.ViewCount,
    em.AnswerCount,
    em.CommentCount,
    em.CommentEngagement,
    em.EditCount,
    em.LinkCount,
    ROUND(em.HoursActive::numeric, 2) as HoursActive,
    em.YearlyRank,
    em.AuthorTotalScore,
    STRING_AGG(DISTINCT tp.TagName, ', ' ORDER BY tp.TagName) as RelevantTags,
    AVG(tp.AvgScore) as AvgTagScore,
    AVG(tp.AvgViews) as AvgTagViews,
    COUNT(DISTINCT ans.Id) as ActualAnswers,
    AVG(ans.Score) as AvgAnswerScore,
    MAX(ans.Score) as BestAnswerScore,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) as TotalBountyAmount,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 5) as FavoriteCount,
    em.PrevPostScore,
    em.NextPostScore,
    CASE 
        WHEN em.Score > COALESCE(em.PrevPostScore, 0) AND em.Score > COALESCE(em.NextPostScore, 0) THEN 'Peak'
        WHEN em.Score < COALESCE(em.PrevPostScore, 999999) AND em.Score < COALESCE(em.NextPostScore, 999999) THEN 'Valley'
        ELSE 'Normal'
    END as PerformanceTrend,
    ROUND((em.Score::numeric / NULLIF(em.ViewCount, 0)) * 1000, 4) as ScorePerThousandViews
FROM EngagementMetrics em
INNER JOIN Posts p ON em.PostId = p.Id
LEFT JOIN TagPerformance tp ON p.Tags LIKE '%<' || tp.TagName || '>%'
LEFT JOIN Posts ans ON em.PostId = ans.ParentId AND ans.PostTypeId = 2
LEFT JOIN Votes v ON em.PostId = v.PostId
WHERE tp.PostCount IS NOT NULL
GROUP BY em.PostId, em.Title, em.AuthorName, em.Score, em.ViewCount, em.AnswerCount, 
         em.CommentCount, em.CommentEngagement, em.EditCount, em.LinkCount, 
         em.HoursActive, em.YearlyRank, em.AuthorTotalScore, em.PrevPostScore, em.NextPostScore
HAVING COUNT(DISTINCT ans.Id) >= 1
ORDER BY em.Score * AVG(tp.AvgScore) DESC, em.ViewCount DESC
LIMIT 500;
