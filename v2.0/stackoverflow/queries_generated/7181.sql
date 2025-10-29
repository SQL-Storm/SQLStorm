-- {"query": "7181.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2337} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationTier,
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.PostTypeId = 1) as QuestionCount,
        (SELECT COUNT(*) 
         FROM Posts p3 
         WHERE p3.OwnerUserId = u.Id 
         AND p3.PostTypeId = 2) as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        COALESCE(p.Tags, '') as CleanTags,
        ISNULL(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        DATEDIFF(day, p.CreationDate, GETDATE()) as AgeInDays,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankByScore,
        RANK() OVER (ORDER BY p.Score DESC) as GlobalRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) as DenseRank,
        NTILE(100) OVER (ORDER BY p.Score DESC) as Percentile,
        LAG(p.Score, 1) OVER (ORDER BY p.CreationDate) as PreviousScore,
        LEAD(p.Score, 1) OVER (ORDER BY p.CreationDate) as NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgScorePerUser,
        SUM(p.Score) OVER (PARTITION BY p.OwnerUserId) as TotalScorePerUser,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as PostCountPerUser,
        CASE 
            WHEN p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'AboveAverage'
            WHEN p.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'BelowAverage'
            ELSE 'Average'
        END as ScoreStatus
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as Popularity,
        STRING_AGG(
            CASE 
                WHEN p.PostTypeId = 1 THEN p.Title
                ELSE NULL
            END, 
            '; ' 
        ) as SampleQuestions,
        COUNT(DISTINCT p.Id) as QuestionCount,
        AVG(p.Score) as AvgScore
    FROM Tags t
    LEFT JOIN Posts p ON t.TagName = SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.CommentCount,
    us.BadgeCount,
    us.AvgPostScore,
    us.ReputationTier,
    us.QuestionCount,
    us.AnswerCount,
    pa.PostId,
    pa.Title,
    pa.Score,
    pa.ViewCount,
    pa.PostType,
    pa.CleanTags,
    pa.AgeInDays,
    pa.RankByScore,
    pa.GlobalRank,
    pa.Percentile,
    pa.ScoreStatus,
    pa.PreviousScore,
    pa.NextScore,
    pa.AvgScorePerUser,
    ta.TagName,
    ta.Popularity,
    ta.QuestionCount,
    ta.AvgScore,
    CASE 
        WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) 
        AND us.Reputation > 1000 
        AND us.PostCount > 10 
        THEN 'HighValue'
        WHEN pa.Score < 0 
        AND pa.AgeInDays > 365 
        AND pa.ScoreStatus = 'BelowAverage' 
        THEN 'LowQuality'
        ELSE 'Standard'
    END as ContentQuality,
    ISNULL((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 2), 0) as Upvotes,
    ISNULL((SELECT COUNT(*) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 3), 0) as Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = pa.PostId) as CommentCount,
    (SELECT COUNT(DISTINCT UserId) FROM Votes v WHERE v.PostId = pa.PostId AND v.VoteTypeId = 5) as FavoriteCount,
    (SELECT STRING_AGG(CONVERT(VARCHAR(10), UserId), ',') 
     FROM Votes v 
     WHERE v.PostId = pa.PostId AND v.VoteTypeId = 8) as BountyUsers,
    CASE 
        WHEN pa.CreationDate = (SELECT MIN(CreationDate) FROM Posts WHERE OwnerUserId = us.UserId) 
        THEN 'FirstPost'
        WHEN pa.CreationDate = (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = us.UserId) 
        THEN 'LatestPost'
        ELSE 'Regular'
    END as PostTimeline,
    COALESCE(pa.AnswerCount, 0) as AnswerCount,
    COALESCE(pa.CommentCount, 0) as CommentCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = pa.PostId AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as EditCount,
    CASE 
        WHEN pa.HasAcceptedAnswer > 0 THEN 'Accepted'
        ELSE 'NotAccepted'
    END as AcceptanceStatus,
    CASE 
        WHEN pa.AgeInDays > 365 THEN 'Legacy'
        WHEN pa.AgeInDays > 30 THEN 'Recent'
        ELSE 'Fresh'
    END as TimeCategory,
    ((us.PostCount * 100.0) / 
     (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = us.UserId)) as RelativePostCount,
    NULLIF((pa.Score * 100.0) / (SELECT MAX(Score) FROM Posts), 0) as ScorePercentage,
    (SELECT COUNT(*) 
     FROM PostHistory ph 
     WHERE ph.PostId = pa.PostId 
     AND ph.UserId = us.UserId) as SelfEdits,
    CASE 
        WHEN us.PostCount = 0 THEN 0
        ELSE (SELECT AVG(Score) FROM Posts WHERE OwnerUserId = us.UserId)
    END as AvgUserScore,
    CASE 
        WHEN pa.AgeInDays > 365 AND pa.Score > 100 AND pa.ViewCount > 1000 THEN 'Trending'
        ELSE 'Stable'
    END as TrendState,
    (SELECT STRING_AGG(p2.Title, ' | ') 
     FROM Posts p2 
     WHERE p2.ParentId = pa.PostId OR p2.Id = pa.PostId) as TitleChain,
    'User_' + CAST(us.UserId AS VARCHAR(10)) + '_Post_' + CAST(pa.PostId AS VARCHAR(10)) as CombinedKey,
    ABS(pa.Score - pa.AvgScorePerUser) as ScoreDeviation,
    (SELECT COUNT(*) 
     FROM PostLinks pl 
     WHERE pl.PostId = pa.PostId OR pl.RelatedPostId = pa.PostId) as LinkCount,
    CASE 
        WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5 THEN 'HighlyVoted'
        WHEN pa.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'LowVoted'
        ELSE 'NormalVoted'
    END as VotingCategory,
    (SELECT TOP 1 ph.Text 
     FROM PostHistory ph 
     WHERE ph.PostId = pa.PostId 
     AND ph.PostHistoryTypeId = 2 
     ORDER BY ph.CreationDate DESC) as RecentBody,
    (SELECT COUNT(*) 
     FROM Badges b 
     WHERE b.UserId = us.UserId 
     AND b.Name LIKE '%Tag%') as TagBadgeCount,
    (SELECT COUNT(*) 
     FROM Posts p4 
     WHERE p4.OwnerUserId = us.UserId 
     AND p4.PostTypeId = 1 
     AND p4.CreationDate > DATEADD(month, -6, GETDATE())) as RecentQuestions,
    (SELECT COUNT(*) 
     FROM Posts p5 
     WHERE p5.OwnerUserId = us.UserId 
     AND p5.PostTypeId = 2 
     AND p5.CreationDate > DATEADD(month, -6, GETDATE())) as RecentAnswers,
    CASE 
        WHEN us.PostCount > 0 THEN (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = us.UserId AND Score > 0) * 100.0 / us.PostCount
        ELSE NULL
    END as PositiveScoreRatio
FROM UserStats us
INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
LEFT JOIN TagAnalysis ta ON pa.CleanTags LIKE '%' + ta.TagName + '%'
WHERE us.PostCount > 0
AND pa.Score IS NOT NULL
AND (
    (pa.Percentile <= 10 AND pa.ScoreStatus = 'AboveAverage') 
    OR 
    (pa.AgeInDays > 365 AND pa.Score < 0 AND pa.ScoreStatus = 'BelowAverage')
)
AND us.ReputationTier IN ('Elite', 'Expert')
ORDER BY pa.Score DESC, us.Reputation DESC, pa.CreationDate DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;