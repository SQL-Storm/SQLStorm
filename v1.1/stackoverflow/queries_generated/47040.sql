-- {"query": "47040.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 2061}

WITH RECURSIVE tag_hierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        COUNT(DISTINCT p.Id) as QuestionCount,
        1 as Level
    FROM Tags t
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 1
        AND t.Count > 1000
    GROUP BY t.Id, t.TagName
    
    UNION ALL
    
    SELECT 
        t.Id,
        t.TagName,
        th.QuestionCount,
        th.Level + 1
    FROM Tags t
    INNER JOIN tag_hierarchy th ON th.Id != t.Id
    WHERE th.Level < 3
),
user_expertise AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        t.TagName,
        COUNT(DISTINCT p.Id) as AnswerCount,
        SUM(p.Score) as TotalScore,
        AVG(p.Score) as AvgScore,
        MAX(p.Score) as MaxScore,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId = p.Id THEN p.Id END) as AcceptedAnswers,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) as MedianScore,
        STDDEV(p.Score) as ScoreStdDev
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    INNER JOIN Posts q ON q.Id = p.ParentId
    INNER JOIN Tags t ON q.Tags LIKE '%<' || t.TagName || '>%'
    WHERE p.PostTypeId = 2
        AND u.Reputation > 5000
        AND p.Score > 0
    GROUP BY u.Id, u.DisplayName, t.TagName
    HAVING COUNT(DISTINCT p.Id) >= 10
),
monthly_activity AS (
    SELECT 
        DATE_TRUNC('month', p.CreationDate) as ActivityMonth,
        u.Id as UserId,
        COUNT(DISTINCT p.Id) as PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        AVG(p.Score) as AvgScore,
        SUM(p.ViewCount) as TotalViews,
        COUNT(DISTINCT c.Id) as CommentsMade
    FROM Users u
    INNER JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id 
        AND DATE_TRUNC('month', c.CreationDate) = DATE_TRUNC('month', p.CreationDate)
    WHERE p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY DATE_TRUNC('month', p.CreationDate), u.Id
),
badge_patterns AS (
    SELECT 
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        COUNT(*) as BadgeCount,
        MIN(b.Date) as FirstEarned,
        MAX(b.Date) as LastEarned,
        EXTRACT(EPOCH FROM (MAX(b.Date) - MIN(b.Date))) / 86400.0 as DaysToRepeat,
        LAG(b.Date) OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date) as PrevDate,
        LEAD(b.Date) OVER (PARTITION BY b.UserId, b.Name ORDER BY b.Date) as NextDate
    FROM Badges b
    WHERE b.TagBased = '0'
    GROUP BY b.UserId, b.Name, b.Class, b.Date
),
edit_patterns AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT ph.PostId) as EditedPosts,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 END) as Edits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (7,8,9) THEN 1 END) as Rollbacks,
        AVG(LENGTH(ph.Text)) as AvgEditSize,
        STDDEV(LENGTH(ph.Text)) as EditSizeStdDev,
        COUNT(DISTINCT DATE(ph.CreationDate)) as ActiveEditDays
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
        AND ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
),
network_analysis AS (
    SELECT 
        p1.OwnerUserId as User1,
        p2.OwnerUserId as User2,
        COUNT(DISTINCT p1.Id) as SharedQuestions,
        AVG(ABS(p1.Score - p2.Score)) as ScoreDifference,
        CORR(p1.Score, p2.Score) as ScoreCorrelation,
        COUNT(DISTINCT pl.Id) as LinkedPosts
    FROM Posts p1
    INNER JOIN Posts p2 ON p2.ParentId = p1.Id
        AND p1.OwnerUserId != p2.OwnerUserId
    LEFT JOIN PostLinks pl ON (pl.PostId = p1.Id AND pl.RelatedPostId = p2.Id)
        OR (pl.PostId = p2.Id AND pl.RelatedPostId = p1.Id)
    WHERE p1.PostTypeId = 1 
        AND p2.PostTypeId = 2
        AND p1.OwnerUserId IS NOT NULL
        AND p2.OwnerUserId IS NOT NULL
    GROUP BY p1.OwnerUserId, p2.OwnerUserId
    HAVING COUNT(DISTINCT p1.Id) >= 5
)
SELECT 
    ue.UserId,
    ue.DisplayName,
    ue.TagName,
    ue.TotalScore as ExpertiseScore,
    ue.AcceptedAnswers,
    ma.PostCount as RecentMonthlyPosts,
    ma.AvgScore as RecentAvgScore,
    bp.BadgeCount as GoldBadges,
    bp.DaysToRepeat as BadgeVelocity,
    ep.Edits as TotalEdits,
    ep.AvgEditSize,
    na.SharedQuestions,
    na.ScoreCorrelation as NetworkCorrelation,
    DENSE_RANK() OVER (PARTITION BY ue.TagName ORDER BY ue.TotalScore DESC) as TagRank,
    PERCENT_RANK() OVER (ORDER BY ma.TotalViews DESC) as ViewPercentile,
    NTILE(10) OVER (ORDER BY ep.ActiveEditDays DESC) as EditActivityDecile,
    ROW_NUMBER() OVER (ORDER BY ue.TotalScore * LOG(ma.PostCount + 1) * COALESCE(bp.BadgeCount, 1) DESC) as OverallRank
FROM user_expertise ue
LEFT JOIN (
    SELECT UserId, PostCount, AvgScore, TotalViews
    FROM monthly_activity
    WHERE ActivityMonth = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
) ma ON ma.UserId = ue.UserId
LEFT JOIN (
    SELECT UserId, COUNT(*) as BadgeCount, AVG(DaysToRepeat) as DaysToRepeat
    FROM badge_patterns
    WHERE Class = 1
    GROUP BY UserId
) bp ON bp.UserId = ue.UserId
LEFT JOIN edit_patterns ep ON ep.UserId = ue.UserId
LEFT JOIN (
    SELECT User1, COUNT(*) as SharedQuestions, AVG(ScoreCorrelation) as ScoreCorrelation
    FROM network_analysis
    GROUP BY User1
) na ON na.User1 = ue.UserId
WHERE ue.TotalScore > 100
ORDER BY OverallRank
LIMIT 100;
