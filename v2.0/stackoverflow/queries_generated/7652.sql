-- {"query": "7652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1948} 
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
        COALESCE(SUM(p.Score), 0) as TotalScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT p.Id) DESC) as PostRank,
        RANK() OVER (ORDER BY u.Reputation DESC) as RepRank,
        DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT b.Id) DESC) as BadgeRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.AccountId IS NOT NULL
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
        p.ParentId,
        p.PostTypeId,
        p.AnswerCount,
        p.CommentCount,
        p.Tags,
        p.FavoriteCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
            WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
            WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
            ELSE 'Unknown'
        END as PostTypeName,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1
            WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN 1
            ELSE 0
        END as IsAnswered,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High Traffic'
            WHEN p.ViewCount > 100 THEN 'Medium Traffic'
            WHEN p.ViewCount > 0 THEN 'Low Traffic'
            ELSE 'No Traffic'
        END as TrafficLevel,
        CASE 
            WHEN p.Score > 100 THEN 'Highly Rated'
            WHEN p.Score > 50 THEN 'Moderately Rated'
            WHEN p.Score > 0 THEN 'Low Rated'
            ELSE 'Not Rated'
        END as RatingLevel,
        DATEDIFF(DAY, p.CreationDate, GETDATE()) as AgeInDays,
        CASE 
            WHEN p.CreationDate >= DATEADD(MONTH, -1, GETDATE()) THEN 'Recent'
            WHEN p.CreationDate >= DATEADD(MONTH, -6, GETDATE()) THEN 'Medium Age'
            ELSE 'Old'
        END as PostAgeGroup
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
ComplexJoinAnalysis AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.PostTypeName,
        pa.IsAnswered,
        pa.TrafficLevel,
        pa.RatingLevel,
        pa.AgeInDays,
        pa.PostAgeGroup,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Pro'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as UserLevel,
        COALESCE(b.Name, 'No Badge') as MostRecentBadge,
        COALESCE(b.Date, '1900-01-01') as BadgeDate,
        CASE 
            WHEN COALESCE(pa.AcceptedAnswerId, 0) > 0 THEN (
                SELECT TOP 1 p2.Score 
                FROM Posts p2 
                WHERE p2.Id = pa.AcceptedAnswerId
            ) 
            ELSE NULL 
        END as AcceptedAnswerScore,
        CASE 
            WHEN pa.PostTypeId = 1 THEN (
                SELECT COUNT(*) 
                FROM Votes v 
                WHERE v.PostId = pa.PostId 
                AND v.VoteTypeId = 2
            )
            ELSE 0 
        END as UpvoteCount
    FROM PostAnalysis pa
    INNER JOIN Users u ON pa.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            b1.UserId,
            b1.Name,
            b1.Date,
            ROW_NUMBER() OVER (PARTITION BY b1.UserId ORDER BY b1.Date DESC) as rn
        FROM Badges b1
    ) b ON b.UserId = u.Id AND b.rn = 1
    WHERE pa.Score > 0
),
FinalAggregation AS (
    SELECT 
        f1.PostId,
        f1.Title,
        f1.Score,
        f1.ViewCount,
        f1.PostTypeName,
        f1.IsAnswered,
        f1.TrafficLevel,
        f1.RatingLevel,
        f1.AgeInDays,
        f1.PostAgeGroup,
        f1.OwnerName,
        f1.OwnerReputation,
        f1.UserLevel,
        f1.MostRecentBadge,
        f1.BadgeDate,
        f1.AcceptedAnswerScore,
        f1.UpvoteCount,
        PERCENT_RANK() OVER (ORDER BY f1.Score DESC) as ScorePercentile,
        CUME_DIST() OVER (ORDER BY f1.ViewCount) as ViewCountPercentile,
        NTILE(4) OVER (ORDER BY f1.Score DESC) as ScoreQuartile,
        LAG(f1.Score, 1) OVER (ORDER BY f1.Score DESC) as PreviousScore,
        LEAD(f1.Score, 1) OVER (ORDER BY f1.Score DESC) as NextScore,
        AVG(f1.Score) OVER (ORDER BY f1.Score DESC ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) as MovingAverage,
        COUNT(*) OVER () as TotalPosts,
        SUM(f1.Score) OVER () as TotalScore,
        CASE 
            WHEN f1.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Above Average'
            WHEN f1.Score < (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) THEN 'Below Average'
            ELSE 'Average'
        END as ScoreComparison,
        REPLICATE('*', f1.Score / 10) as ScoreVisualization,
        CASE 
            WHEN f1.Tags IS NOT NULL AND LEN(f1.Tags) > 0 THEN 
                STRING_AGG(SUBSTRING(f1.Tags, n.number, 1), ', ') 
                WITHIN GROUP (ORDER BY n.number)
            ELSE 'No Tags'
        END as ExtractedTags,
        CONCAT(
            'Post ', f1.PostId, ' by ', f1.OwnerName, 
            ' (', f1.PostTypeName, ') - Score: ', f1.Score,
            ', Views: ', f1.ViewCount
        ) as PostSummary
    FROM ComplexJoinAnalysis f1
    CROSS JOIN (
        SELECT 1 as number UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL 
        SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL 
        SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL 
        SELECT 10
    ) n
    WHERE n.number <= LEN(ISNULL(f1.Tags, ''))
)
SELECT 
    PostId,
    Title,
    Score,
    ViewCount,
    PostTypeName,
    IsAnswered,
    TrafficLevel,
    RatingLevel,
    AgeInDays,
    PostAgeGroup,
    OwnerName,
    OwnerReputation,
    UserLevel,
    MostRecentBadge,
    BadgeDate,
    AcceptedAnswerScore,
    UpvoteCount,
    ScorePercentile,
    ViewCountPercentile,
    ScoreQuartile,
    PreviousScore,
    NextScore,
    MovingAverage,
    TotalPosts,
    TotalScore,
    ScoreComparison,
    ScoreVisualization,
    ExtractedTags,
    PostSummary,
    ROW_NUMBER() OVER (ORDER BY Score DESC) as RankByScore,
    DENSE_RANK() OVER (ORDER BY ViewCount DESC) as RankByViews,
    RANK() OVER (ORDER BY AgeInDays ASC) as RankByAge
FROM FinalAggregation
WHERE Score > (SELECT AVG(Score) FROM Posts) OR ViewCount > 100
ORDER BY Score DESC, ViewCount DESC
OFFSET 0 ROWS
FETCH NEXT 1000 ROWS ONLY;