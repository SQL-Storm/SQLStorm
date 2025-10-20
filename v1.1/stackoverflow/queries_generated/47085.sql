-- {"query": "47085.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 194990, "output_tokens": 171825} 

WITH RECURSIVE TagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        CAST(t.TagName AS varchar(1000)) AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        CAST(th.TagPath || ' -> ' || t2.TagName AS varchar(1000)),
        th.Level + 1
    FROM Tags t2
    INNER JOIN TagHierarchy th ON th.Id != t2.Id
    INNER JOIN Posts p1 ON p1.Tags LIKE '%<' || th.TagName || '>%'
    INNER JOIN Posts p2 ON p2.Id = p1.Id AND p2.Tags LIKE '%<' || t2.TagName || '>%'
    WHERE th.Level < 3 AND t2.Count > 5000
    GROUP BY t2.Id, t2.TagName, t2.Count, th.TagPath, th.Level
),
UserMetrics AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) AS AcceptedAnswers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STDDEV(p.Score) AS ScoreStdDev
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT ph.Id) AS EditCount,
        COUNT(DISTINCT pl.Id) AS LinkedPostCount,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate))/3600 AS HoursToLastActivity,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, CURRENT_TIMESTAMP) - p.CreationDate))/86400 AS DaysUntilClosed,
        CASE 
            WHEN p.ViewCount > 0 THEN CAST(p.Score AS FLOAT) / p.ViewCount * 1000 
            ELSE 0 
        END AS ScorePerThousandViews,
        DENSE_RANK() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC) AS MonthlyRank
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, 
             p.FavoriteCount, p.LastActivityDate, p.CreationDate, p.ClosedDate
),
TagCorrelations AS (
    SELECT 
        t1.TagName AS Tag1,
        t2.TagName AS Tag2,
        COUNT(DISTINCT p.Id) AS CoOccurrences,
        CAST(COUNT(DISTINCT p.Id) AS FLOAT) / NULLIF(t1.Count, 0) AS Tag1Correlation,
        CAST(COUNT(DISTINCT p.Id) AS FLOAT) / NULLIF(t2.Count, 0) AS Tag2Correlation,
        AVG(p.Score) AS AvgScoreTogether,
        STDDEV(p.Score) AS ScoreStdDevTogether
    FROM Tags t1
    CROSS JOIN Tags t2
    INNER JOIN Posts p ON p.Tags LIKE '%<' || t1.TagName || '>%' 
                       AND p.Tags LIKE '%<' || t2.TagName || '>%'
    WHERE t1.Id < t2.Id 
        AND t1.Count > 1000 
        AND t2.Count > 1000
    GROUP BY t1.TagName, t2.TagName, t1.Count, t2.Count
    HAVING COUNT(DISTINCT p.Id) > 100
)
SELECT 
    um.DisplayName,
    um.Reputation,
    um.PostCount,
    um.QuestionCount,
    um.AnswerCount,
    um.AcceptedAnswers,
    ROUND(um.AvgPostScore, 2) AS AvgPostScore,
    um.TotalScore,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    ROUND(um.MedianScore, 2) AS MedianScore,
    ROUND(um.ScoreStdDev, 2) AS ScoreStdDev,
    COUNT(DISTINCT pe.PostId) AS HighEngagementPosts,
    AVG(pe.ScorePerThousandViews) AS AvgScorePerThousandViews,
    STRING_AGG(DISTINCT th.TagPath, '; ' ORDER BY th.TagPath) AS TagPaths,
    COUNT(DISTINCT tc.Tag1 || '-' || tc.Tag2) AS TagCombinations,
    AVG(tc.AvgScoreTogether) AS AvgTagComboScore,
    SUM(CASE WHEN pe.MonthlyRank <= 10 THEN 1 ELSE 0 END) AS Top10MonthlyPosts,
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY pe.VoteCount) AS P90VoteCount,
    CORR(um.Reputation, um.TotalScore) OVER () AS ReputationScoreCorrelation,
    LAG(um.TotalScore, 1) OVER (ORDER BY um.Reputation DESC) AS PrevUserTotalScore,
    LEAD(um.TotalScore, 1) OVER (ORDER BY um.Reputation DESC) AS NextUserTotalScore,
    NTILE(100) OVER (ORDER BY um.Reputation) AS ReputationPercentile,
    ROW_NUMBER() OVER (PARTITION BY um.GoldBadges ORDER BY um.TotalScore DESC) AS RankWithinGoldBadgeGroup
FROM UserMetrics um
LEFT JOIN Posts p ON p.OwnerUserId = um.Id
LEFT JOIN PostEngagement pe ON pe.PostId = p.Id AND pe.Score > 10
LEFT JOIN TagHierarchy th ON p.Tags LIKE '%<' || th.TagName || '>%'
LEFT JOIN TagCorrelations tc ON p.Tags LIKE '%<' || tc.Tag1 || '>%' AND p.Tags LIKE '%<' || tc.Tag2 || '>%'
WHERE um.PostCount > 10
    AND um.AvgPostScore > 1
GROUP BY um.Id, um.DisplayName, um.Reputation, um.PostCount, um.QuestionCount, 
         um.AnswerCount, um.AcceptedAnswers, um.AvgPostScore, um.TotalScore,
         um.GoldBadges, um.SilverBadges, um.BronzeBadges, um.MedianScore, um.ScoreStdDev
HAVING COUNT(DISTINCT pe.PostId) > 0
ORDER BY um.Reputation DESC, um.TotalScore DESC
LIMIT 100;
