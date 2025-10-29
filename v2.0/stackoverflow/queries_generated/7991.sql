-- {"query": "7991.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2278} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        COUNT(DISTINCT v.Id) as VoteCount,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(u.CreationDate) as LatestActivity,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ',') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalPostScore DESC, PostCount DESC) as RankByScore,
        RANK() OVER (ORDER BY Reputation DESC, ViewCount DESC) as RankByReputation,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC, VoteCount DESC) as RankByActivity
    FROM UserStats
),
FilteredPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Unknown'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'VeryLowVoted'
        END as ScoreCategory,
        COALESCE(LEAD(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate), 0) as NextPostScore,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as UserPostSequence,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        COALESCE(SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId), 0) as TotalUserViews,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'HighlyAnswered'
            WHEN p.AnswerCount > 5 THEN 'ModeratelyAnswered'
            WHEN p.AnswerCount > 0 THEN 'SlightlyAnswered'
            ELSE 'Unanswered'
        END as AnswerStatus
    FROM Posts p
    WHERE p.CreationDate > '2020-01-01'
        AND p.Score IS NOT NULL
        AND p.ViewCount IS NOT NULL
),
PostAnalysis AS (
    SELECT 
        fp.Id,
        fp.PostTypeId,
        fp.OwnerUserId,
        fp.Score,
        fp.ViewCount,
        fp.CreationDate,
        fp.Title,
        fp.Tags,
        fp.PostType,
        fp.ScoreCategory,
        fp.AnswerStatus,
        fp.UserPostSequence,
        fp.AvgScorePerUser,
        fp.TotalUserViews,
        fp.NextPostScore,
        CASE 
            WHEN fp.Score > fp.AvgScorePerUser THEN 'AboveAverage'
            WHEN fp.Score < fp.AvgScorePerUser THEN 'BelowAverage'
            ELSE 'Average'
        END as PerformanceAgainstUserAvg,
        CASE 
            WHEN fp.ViewCount > 1000 THEN 'Viral'
            WHEN fp.ViewCount > 500 THEN 'Popular'
            WHEN fp.ViewCount > 100 THEN 'Notable'
            ELSE 'LowVisibility'
        END as VisibilityLevel,
        DENSE_RANK() OVER (ORDER BY fp.ViewCount DESC, fp.Score DESC) as PopularityRank
    FROM FilteredPosts fp
),
UserPostAnalysis AS (
    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.PostCount,
        r.TotalPostScore,
        r.TotalViews,
        r.RankByScore,
        r.RankByReputation,
        r.RankByActivity,
        COALESCE(SUM(pa.Score), 0) as UserTotalScore,
        COALESCE(AVG(pa.Score), 0) as AvgUserPostScore,
        MAX(pa.ViewCount) as MaxUserViewCount,
        COUNT(pa.Id) as UserPostCount,
        STRING_AGG(DISTINCT pa.Tags, ',') as UserTags
    FROM RankedUsers r
    LEFT JOIN PostAnalysis pa ON r.UserId = pa.OwnerUserId
    GROUP BY r.UserId, r.DisplayName, r.Reputation, r.PostCount, r.TotalPostScore, r.TotalViews, r.RankByScore, r.RankByReputation, r.RankByActivity
),
CrossPostAnalysis AS (
    SELECT 
        pa1.Id as Post1Id,
        pa2.Id as Post2Id,
        pa1.Title as Post1Title,
        pa2.Title as Post2Title,
        pa1.Score as Post1Score,
        pa2.Score as Post2Score,
        pa1.Tags as Post1Tags,
        pa2.Tags as Post2Tags,
        pa1.ViewCount as Post1Views,
        pa2.ViewCount as Post2Views,
        pa1.AnswerStatus as Post1AnswerStatus,
        pa2.AnswerStatus as Post2AnswerStatus,
        DATEDIFF(day, pa1.CreationDate, pa2.CreationDate) as TimeDifferenceDays,
        CASE 
            WHEN LENGTH(pa1.Tags) > LENGTH(pa2.Tags) THEN 'Post1HasMoreTags'
            WHEN LENGTH(pa2.Tags) > LENGTH(pa1.Tags) THEN 'Post2HasMoreTags'
            ELSE 'SameTagLength'
        END as TagLengthComparison,
        CASE 
            WHEN pa1.Score > pa2.Score THEN 1
            WHEN pa2.Score > pa1.Score THEN -1
            ELSE 0
        END as ScoreComparison,
        ABS(pa1.Score - pa2.Score) as ScoreDifference,
        (pa1.ViewCount + pa2.ViewCount) / 2.0 as AverageViews,
        (pa1.Score + pa2.Score) / 2.0 as AverageScore
    FROM PostAnalysis pa1
    INNER JOIN PostAnalysis pa2 ON pa1.Id != pa2.Id
    WHERE pa1.Score IS NOT NULL 
        AND pa2.Score IS NOT NULL
        AND pa1.ViewCount IS NOT NULL
        AND pa2.ViewCount IS NOT NULL
        AND pa1.CreationDate < pa2.CreationDate
        AND ABS(DATEDIFF(day, pa1.CreationDate, pa2.CreationDate)) <= 30
),
FinalResult AS (
    SELECT 
        upa.UserId,
        upa.DisplayName,
        upa.Reputation,
        upa.PostCount,
        upa.UserTotalScore,
        upa.AvgUserPostScore,
        upa.MaxUserViewCount,
        upa.UserPostCount,
        upa.UserTags,
        upa.RankByScore,
        upa.RankByReputation,
        upa.RankByActivity,
        COALESCE(SUM(CASE WHEN cpa.ScoreComparison = 1 THEN 1 ELSE 0 END), 0) as PostsAboveAvgScore,
        COALESCE(SUM(CASE WHEN cpa.ScoreComparison = -1 THEN 1 ELSE 0 END), 0) as PostsBelowAvgScore,
        COALESCE(AVG(cpa.ScoreDifference), 0) as AvgScoreDifference,
        COUNT(cpa.Post1Id) as CrossPostComparisons,
        STRING_AGG(CONCAT('Post-', cpa.Post2Id, ':', cpa.ScoreDifference), ', ') as ScoreDifferenceDetails,
        CASE 
            WHEN upa.UserTotalScore > 10000 THEN 'Elite'
            WHEN upa.UserTotalScore > 5000 THEN 'Veteran'
            WHEN upa.UserTotalScore > 1000 THEN 'Experienced'
            ELSE 'Novice'
        END as UserLevel,
        STRING_AGG(DISTINCT CASE WHEN pa.AnswerStatus = 'HighlyAnswered' THEN pa.Title ELSE NULL END, ' | ') as HighlyAnsweredPosts,
        STRING_AGG(DISTINCT CASE WHEN pa.VisibilityLevel = 'Viral' THEN pa.Title ELSE NULL END, ' | ') as ViralPosts,
        CASE 
            WHEN COUNT(pa.Id) > 0 THEN 
                AVG(CASE WHEN pa.ViewCount > 0 THEN pa.ViewCount END)
            ELSE 0
        END as AvgPostViews
    FROM UserPostAnalysis upa
    LEFT JOIN CrossPostAnalysis cpa ON upa.UserId = (
        SELECT pa.OwnerUserId 
        FROM PostAnalysis pa 
        WHERE pa.Id IN (cpa.Post1Id, cpa.Post2Id) 
        LIMIT 1
    )
    LEFT JOIN PostAnalysis pa ON upa.UserId = pa.OwnerUserId
    WHERE upa.Reputation > 100
    GROUP BY upa.UserId, upa.DisplayName, upa.Reputation, upa.PostCount, upa.UserTotalScore, upa.AvgUserPostScore, upa.MaxUserViewCount, upa.UserPostCount, upa.UserTags, upa.RankByScore, upa.RankByReputation, upa.RankByActivity
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    UserTotalScore,
    AvgUserPostScore,
    MaxUserViewCount,
    UserPostCount,
    UserTags,
    RankByScore,
    RankByReputation,
    RankByActivity,
    PostsAboveAvgScore,
    PostsBelowAvgScore,
    AvgScoreDifference,
    CrossPostComparisons,
    ScoreDifferenceDetails,
    UserLevel,
    HighlyAnsweredPosts,
    ViralPosts,
    AvgPostViews
FROM FinalResult
WHERE UserTotalScore > 1000
    AND CrossPostComparisons > 5
    AND AvgPostViews > 100
ORDER BY UserTotalScore DESC, AvgScoreDifference DESC
LIMIT 1000;