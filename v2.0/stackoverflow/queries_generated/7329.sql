-- {"query": "7329.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1564} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(u.LastAccessDate) AS LastAccessDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC, UpVotes DESC) AS RankByReputation,
        DENSE_RANK() OVER (ORDER BY QuestionCount DESC, AnswerCount DESC) AS RankByActivity,
        NTILE(100) OVER (ORDER BY Views DESC) AS PercentileByViews
    FROM UserStats
),
TopTags AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank,
        LAG(t.Count) OVER (ORDER BY t.Count DESC) - t.Count AS CountDifference
    FROM Tags t
    WHERE t.Count > 1000
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        u.DisplayName AS OwnerName,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'NonVoted'
        END AS ScoreCategory,
        COALESCE(NULLIF(p.Title, ''), 'No Title') AS EffectiveTitle,
        ISNULL(p.Tags, '') AS TagsList
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATEADD(YEAR, -1, GETDATE()) 
      AND p.PostTypeId IN (1, 2)
),
QualityPosts AS (
    SELECT 
        pa.*,
        CASE 
            WHEN pa.Score > 10 AND pa.ViewCount > 1000 AND pa.AnswerCount > 2 THEN 'HighQuality'
            WHEN pa.Score > 5 AND pa.ViewCount > 500 AND pa.AnswerCount > 1 THEN 'MediumQuality'
            ELSE 'LowQuality'
        END AS QualityLevel,
        DATEDIFF(DAY, pa.CreationDate, GETDATE()) AS DaysSinceCreation,
        ABS(pa.Score - AVG(pa.Score) OVER()) AS ScoreDeviation,
        RANK() OVER (PARTITION BY pa.PostTypeId ORDER BY pa.Score DESC) AS ScoreRankByType
    FROM PostAnalysis pa
),
TagAnalysis AS (
    SELECT 
        ta.TagName,
        ta.Count,
        ta.ExcerptPostId,
        ta.WikiPostId,
        ta.TagRank,
        ta.CountDifference,
        CASE 
            WHEN ta.Count > 5000 THEN 'Trending'
            WHEN ta.Count > 2000 THEN 'Popular'
            ELSE 'Niche'
        END AS PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY ta.Count DESC) AS PopularityRank,
        LAG(ta.Count) OVER (ORDER BY ta.Count DESC) AS PreviousCount
    FROM TopTags ta
)
SELECT 
    'Performance Benchmark Report' AS ReportTitle,
    COUNT(DISTINCT ru.UserId) AS TotalUsers,
    COUNT(DISTINCT pq.PostId) AS TotalPosts,
    COUNT(DISTINCT ta.TagName) AS TotalTags,
    AVG(ru.Reputation) AS AvgReputation,
    MAX(ru.Reputation) AS MaxReputation,
    MIN(ru.Reputation) AS MinReputation,
    STRING_AGG(DISTINCT ru.DisplayName, ', ') AS TopUsers,
    STRING_AGG(DISTINCT pq.Title, ', ') AS SamplePostTitles,
    STRING_AGG(DISTINCT ta.TagName, ', ') AS PopularTags,
    SUM(CASE WHEN pq.QualityLevel = 'HighQuality' THEN 1 ELSE 0 END) AS HighQualityCount,
    SUM(CASE WHEN pq.QualityLevel = 'MediumQuality' THEN 1 ELSE 0 END) AS MediumQualityCount,
    SUM(CASE WHEN pq.QualityLevel = 'LowQuality' THEN 1 ELSE 0 END) AS LowQualityCount,
    AVG(pq.Score) AS AvgPostScore,
    MAX(pq.Score) AS MaxPostScore,
    MAX(pq.ViewCount) AS MaxViews,
    AVG(pq.DaysSinceCreation) AS AvgDaysSinceCreation,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pq.Score) AS MedianScore,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate >= DATEADD(DAY, -7, GETDATE()) 
          AND p.PostTypeId = 1
    ) AS RecentQuestions,
    (
        SELECT COUNT(*) 
        FROM Posts p 
        WHERE p.CreationDate >= DATEADD(DAY, -7, GETDATE()) 
          AND p.PostTypeId = 2
    ) AS RecentAnswers,
    (
        SELECT COUNT(*) 
        FROM Badges b 
        WHERE b.Date >= DATEADD(DAY, -30, GETDATE())
    ) AS RecentBadges,
    (
        SELECT COUNT(*) 
        FROM Comments c 
        WHERE c.CreationDate >= DATEADD(DAY, -30, GETDATE())
    ) AS RecentComments,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.CreationDate >= DATEADD(DAY, -30, GETDATE())
    ) AS RecentVotes,
    (
        SELECT COUNT(*) 
        FROM PostHistory ph 
        WHERE ph.CreationDate >= DATEADD(DAY, -7, GETDATE())
    ) AS RecentPostHistory,
    (
        SELECT COUNT(*) 
        FROM PostLinks pl 
        WHERE pl.CreationDate >= DATEADD(DAY, -30, GETDATE())
    ) AS RecentPostLinks
FROM RankedUsers ru
FULL OUTER JOIN QualityPosts pq ON 1=1
FULL OUTER JOIN TagAnalysis ta ON 1=1
WHERE ru.Reputation > 1000
  AND pq.PostId IS NOT NULL
  AND ta.TagName IS NOT NULL;