-- {"query": "47072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-4.1-opus", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 165168, "output_tokens": 146663} 

WITH RECURSIVE TagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        CAST(t.TagName AS VARCHAR(1000)) AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.Count > 10000
    
    UNION ALL
    
    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        CAST(th.TagPath || ' -> ' || t2.TagName AS VARCHAR(1000)),
        th.Level + 1
    FROM Tags t2
    INNER JOIN TagHierarchy th ON t2.WikiPostId = th.Id
    WHERE th.Level < 3
),
UserMetrics AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        AVG(p.Score) AS AvgPostScore,
        SUM(p.ViewCount) AS TotalViews,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.Score) AS MedianScore,
        STDDEV(p.Score) AS ScoreStdDev,
        MAX(p.Score) AS MaxScore,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= NOW() - INTERVAL '2 years'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MIN(ph.CreationDate) AS FirstEditDate,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(DISTINCT pl.Id) AS LinkCount,
        EXTRACT(EPOCH FROM (COALESCE(p.ClosedDate, NOW()) - p.CreationDate))/3600 AS HoursToClose,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        ROW_NUMBER() OVER (PARTITION BY DATE_TRUNC('month', p.CreationDate) ORDER BY p.Score DESC) AS MonthlyRank,
        DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevPostScore,
        LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (4, 5, 6)
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId
    WHERE p.PostTypeId = 1
        AND p.CreationDate >= NOW() - INTERVAL '1 year'
        AND p.Score > 0
    GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags, 
             p.AnswerCount, p.FavoriteCount, p.AcceptedAnswerId, p.ClosedDate, p.OwnerUserId
),
TagCorrelation AS (
    SELECT 
        t1.TagName AS Tag1,
        t2.TagName AS Tag2,
        COUNT(*) AS CoOccurrences,
        AVG(pa.Score) AS AvgScoreWithBothTags,
        AVG(pa.ViewCount) AS AvgViewsWithBothTags,
        CORR(pa.Score, pa.ViewCount) AS ScoreViewCorrelation
    FROM Tags t1
    CROSS JOIN Tags t2
    INNER JOIN PostAnalysis pa ON pa.Tags LIKE '%<' || t1.TagName || '>%'
        AND pa.Tags LIKE '%<' || t2.TagName || '>%'
    WHERE t1.Id < t2.Id
        AND t1.Count > 1000
        AND t2.Count > 1000
    GROUP BY t1.TagName, t2.TagName
    HAVING COUNT(*) > 50
)
SELECT 
    um.DisplayName AS UserName,
    um.Reputation,
    um.TotalPosts,
    um.Questions,
    um.Answers,
    ROUND(um.AvgPostScore::NUMERIC, 2) AS AvgPostScore,
    um.MedianScore,
    um.MaxScore,
    um.TotalViews,
    um.GoldBadges,
    um.SilverBadges,
    um.BronzeBadges,
    COUNT(DISTINCT pa.PostId) AS HighQualityQuestions,
    AVG(pa.Score) AS AvgQuestionScore,
    AVG(pa.ViewCount) AS AvgQuestionViews,
    AVG(pa.AnswerCount) AS AvgAnswersPerQuestion,
    AVG(pa.CommentCount) AS AvgCommentsPerQuestion,
    AVG(pa.EditCount) AS AvgEditsPerQuestion,
    SUM(pa.HasAcceptedAnswer)::FLOAT / COUNT(pa.PostId) AS AcceptanceRate,
    AVG(pa.HoursToClose) FILTER (WHERE pa.HoursToClose IS NOT NULL) AS AvgHoursToClose,
    STRING_AGG(DISTINCT tc.Tag2, ', ' ORDER BY tc.CoOccurrences DESC) AS TopCorrelatedTags,
    MAX(tc.CoOccurrences) AS MaxTagCorrelation,
    AVG(tc.ScoreViewCorrelation) AS AvgScoreViewCorr,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY pa.Score) AS Q1Score,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY pa.Score) AS Q3Score,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY pa.ViewCount) AS P95Views,
    CASE 
        WHEN um.Reputation > 50000 THEN 'Expert'
        WHEN um.Reputation > 10000 THEN 'Advanced'
        WHEN um.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserLevel,
    COUNT(DISTINCT DATE_TRUNC('week', pa.CreationDate)) AS ActiveWeeks,
    REGR_SLOPE(pa.Score, EXTRACT(EPOCH FROM pa.CreationDate)) AS ScoreTrend
FROM UserMetrics um
INNER JOIN Posts p ON um.UserId = p.OwnerUserId
INNER JOIN PostAnalysis pa ON p.Id = pa.PostId
LEFT JOIN TagCorrelation tc ON pa.Tags LIKE '%<' || tc.Tag1 || '>%'
WHERE um.Reputation > 100
    AND pa.Score > 5
    AND pa.MonthlyRank <= 100
GROUP BY um.UserId, um.DisplayName, um.Reputation, um.TotalPosts, um.Questions, 
         um.Answers, um.AvgPostScore, um.MedianScore, um.MaxScore, um.TotalViews,
         um.GoldBadges, um.SilverBadges, um.BronzeBadges
HAVING COUNT(DISTINCT pa.PostId) >= 5
ORDER BY um.Reputation DESC, AVG(pa.Score) DESC
LIMIT 100;
