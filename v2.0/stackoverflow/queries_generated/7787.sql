-- {"query": "7787.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1508} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(AVG(p.Score), 0) as AverageScore,
        MAX(p.CreationDate) as LastPostDate,
        COUNT(DISTINCT b.Id) as BadgesCount,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgesList,
        COUNT(DISTINCT c.Id) as CommentsCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.CreationDate >= '2010-01-01' 
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        Views,
        UpVotes,
        DownVotes,
        TotalPosts,
        Questions,
        Answers,
        TotalScore,
        AverageScore,
        LastPostDate,
        BadgesCount,
        BadgesList,
        CommentsCount,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as RankByScore,
        DENSE_RANK() OVER (ORDER BY Views DESC) as RankByViews
    FROM UserActivityStats
),
PostTagAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), ' ') as TagArray,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score > 100 THEN 'High'
            WHEN p.Score > 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreCategory,
        DATEDIFF(DAY, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation
    FROM Posts p
    WHERE p.CreationDate >= '2015-01-01'
),
UserPostActivity AS (
    SELECT 
        pu.UserId,
        pu.DisplayName,
        pu.Reputation,
        pu.TotalPosts,
        pu.Questions,
        pu.Answers,
        pu.TotalScore,
        pu.AverageScore,
        pu.BadgesCount,
        pu.CommentsCount,
        pta.PostId,
        pta.Title,
        pta.Tags,
        pta.Score,
        pta.ViewCount,
        pta.CreationDate,
        pta.PostType,
        pta.ScoreCategory,
        pta.DaysSinceCreation,
        ROW_NUMBER() OVER (PARTITION BY pu.UserId ORDER BY pta.Score DESC, pta.CreationDate DESC) as PostRank,
        RANK() OVER (ORDER BY pu.TotalScore DESC, pu.Reputation DESC) as UserRank
    FROM TopUsers pu
    JOIN PostTagAnalysis pta ON pu.UserId = pta.OwnerUserId
    WHERE pta.Score > 0 OR pta.ViewCount > 10
)
SELECT 
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.TotalPosts,
    upa.Questions,
    upa.Answers,
    upa.TotalScore,
    upa.AverageScore,
    upa.BadgesCount,
    upa.CommentsCount,
    upa.PostId,
    upa.Title,
    upa.Tags,
    upa.Score,
    upa.ViewCount,
    upa.CreationDate,
    upa.PostType,
    upa.ScoreCategory,
    upa.DaysSinceCreation,
    (CASE 
        WHEN upa.Score > 100 THEN 10
        WHEN upa.Score > 50 THEN 5
        ELSE 1
    END) * (CASE 
        WHEN upa.ViewCount > 1000 THEN 10
        WHEN upa.ViewCount > 500 THEN 5
        ELSE 1
    END) as EngagementScore,
    (upa.BadgesCount * 2) + (upa.Answers * 3) + (upa.CommentsCount * 1) as ActivityBonus,
    upa.UserRank,
    upa.PostRank,
    CASE 
        WHEN upa.DaysSinceCreation < 30 THEN 'Recent'
        WHEN upa.DaysSinceCreation < 90 THEN 'Veteran'
        ELSE 'Established'
    END as UserAgeGroup,
    (
        SELECT COUNT(*) 
        FROM UserPostActivity upa2 
        WHERE upa2.UserId = upa.UserId 
        AND upa2.ScoreCategory = 'High'
    ) as HighScorePosts,
    (
        SELECT AVG(uta.Score) 
        FROM PostTagAnalysis uta 
        WHERE uta.OwnerUserId = upa.UserId
    ) as AvgUserPostScore,
    CASE 
        WHEN upa.BadgesCount > 5 THEN 'Awarded'
        ELSE 'Standard'
    END as BadgeStatus,
    (
        SELECT STRING_AGG(uta.Title, ' | ') 
        FROM PostTagAnalysis uta 
        WHERE uta.OwnerUserId = upa.UserId 
        AND uta.Score > (SELECT AVG(Score) FROM PostTagAnalysis)
        LIMIT 5
    ) as HighScoringPosts,
    (
        SELECT COUNT(*) 
        FROM (VALUES 
            (upa.PostType),
            (CASE WHEN upa.Questions > 10 THEN 'Multiple Questions' ELSE NULL END),
            (CASE WHEN upa.Answers > 20 THEN 'Multiple Answers' ELSE NULL END)
        ) v(type)
        WHERE v.type IS NOT NULL
    ) as ActivityIndicators,
    upa.UserRank * upa.PostRank as PerformanceMetric
FROM UserPostActivity upa
WHERE 
    upa.UserRank <= 100 
    AND (upa.PostRank <= 20 OR (upa.PostRank <= 50 AND upa.Score > 20))
    AND upa.DaysSinceCreation >= 0
    AND upa.Score > (
        SELECT AVG(Score) 
        FROM PostTagAnalysis 
        WHERE OwnerUserId = upa.UserId
    )
ORDER BY 
    upa.TotalScore DESC, 
    upa.UserRank ASC, 
    upa.PostRank ASC
LIMIT 50;