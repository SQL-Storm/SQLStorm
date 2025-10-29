-- {"query": "7422.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2301} 
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
        MAX(p.CreationDate) as LastPostDate,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Expert'
            WHEN u.Reputation > 100 THEN 'Member'
            ELSE 'Newbie'
        END as ReputationTier,
        ROUND(AVG(p.Score), 2) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ', ') as AllTags,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) as QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) as AnswerCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as AcceptedAnswers,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        PostCount,
        CommentCount,
        BadgeCount,
        ReputationTier,
        AvgPostScore,
        QuestionCount,
        AnswerCount,
        AcceptedAnswers,
        ReputationRank,
        CASE 
            WHEN PostCount > 0 THEN CAST(AnswerCount AS FLOAT) / PostCount * 100 
            ELSE 0 
        END as AnswerPercentage,
        CASE 
            WHEN QuestionCount > 0 THEN CAST(AcceptedAnswers AS FLOAT) / QuestionCount * 100
            ELSE 0 
        END as AcceptanceRate
    FROM UserStats
    WHERE PostCount > 0 AND Reputation > 100
),
PostAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        p.PostTypeId,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'High'
            WHEN p.ViewCount > 100 THEN 'Medium'
            ELSE 'Low'
        END as ViewCategory,
        DATEDIFF(DAY, p.CreationDate, NOW()) as AgeInDays,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as RankWithinUser,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as UserAvgScore,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        CASE 
            WHEN p.Score > 10 AND p.AnswerCount > 0 THEN 'Engaged'
            WHEN p.Score < 0 THEN 'Unpopular'
            ELSE 'Neutral'
        END as EngagementStatus,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        CASE 
            WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Duplicate'
            WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10) THEN 'Closed'
            ELSE 'Active'
        END as Status,
        CASE 
            WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 THEN 
                ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1)
            ELSE 0 
        END as TagCount
    FROM Posts p
    WHERE p.CreationDate > '2020-01-01'
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as Popularity,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as PopularityRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevTagCount
    FROM Tags t
    WHERE t.Count > 0
),
QualityPosts AS (
    SELECT 
        pa.PostId,
        pa.Title,
        pa.OwnerUserId,
        pa.Score,
        pa.ViewCount,
        pa.CommentCount,
        pa.AnswerCount,
        pa.AgeInDays,
        pa.ViewCategory,
        pa.RankWithinUser,
        pa.PrevScore,
        pa.UserAvgScore,
        pa.ScoreQuartile,
        pa.En EngagementStatus,
        pa.Status,
        pa.TagCount,
        CASE 
            WHEN pa.Score > pa.UserAvgScore AND pa.ViewCount > 50 THEN 'HighQuality'
            WHEN pa.Score < 0 OR pa.ViewCount < 10 THEN 'LowQuality'
            ELSE 'Average'
        END as QualityCategory,
        DENSE_RANK() OVER (ORDER BY pa.Score DESC) as GlobalScoreRank,
        (pa.Score * pa.CommentCount) as ScoreCommentProduct,
        CASE 
            WHEN pa.AnswerCount > 0 THEN CAST(pa.CommentCount AS FLOAT) / pa.AnswerCount
            ELSE 0 
        END as CommentsPerAnswer
    FROM PostAnalysis pa
    WHERE pa.PostTypeId IN (1, 2)
),
FinalAnalysis AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.ReputationTier,
        tu.PostCount,
        tu.CommentCount,
        tu.BadgeCount,
        tu.AvgPostScore,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.AcceptanceRate,
        tu.AnswerPercentage,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CommentCount as PostCommentCount,
        pa.AnswerCount as PostAnswerCount,
        pa.AgeInDays,
        pa.ViewCategory,
        pa.En EngagementStatus,
        pa.Status,
        pa.QualityCategory,
        ta.TagName,
        ta.TagCount as TagUsage,
        ta.Popularity,
        CASE 
            WHEN pa.Status = 'Active' AND pa.ViewCategory = 'High' AND pa.ScoreQuartile = 4 THEN 'TopPerforming'
            WHEN pa.Status = 'Closed' THEN 'Closed'
            WHEN pa.Score < 0 AND pa.ViewCount < 10 THEN 'Underperforming'
            ELSE 'Normal'
        END as PostClassification,
        CASE 
            WHEN pa.RankWithinUser = 1 THEN 'TopPost'
            WHEN pa.RankWithinUser <= 3 THEN 'HighPerforming'
            ELSE 'Regular'
        END as UserPostRanking,
        COALESCE(qa.ScoreCommentProduct, 0) as ScoreCommentProduct,
        COALESCE(qa.CommentsPerAnswer, 0) as CommentsPerAnswer,
        CASE 
            WHEN pa.AgeInDays <= 30 THEN 'Recent'
            WHEN pa.AgeInDays <= 365 THEN 'MidAge'
            ELSE 'Old'
        END as PostAgeCategory,
        ABS(pa.Score - pa.PrevScore) as ScoreChange,
        (tu.Reputation * 0.01 + pa.Score * 0.02) as UserPostScoreWeight,
        CASE 
            WHEN pa.AnswerCount > 5 AND pa.CommentCount > 10 THEN 'HighEngagement'
            WHEN pa.AnswerCount > 1 OR pa.CommentCount > 5 THEN 'SomeEngagement'
            ELSE 'LowEngagement'
        END as EngagementLevel,
        ROW_NUMBER() OVER (ORDER BY pa.Score DESC) as OverallRank,
        RANK() OVER (PARTITION BY tu.ReputationTier ORDER BY pa.Score DESC) as TierRank
    FROM TopUsers tu
    INNER JOIN PostAnalysis pa ON tu.UserId = pa.OwnerUserId
    LEFT JOIN TagAnalysis ta ON EXISTS (
        SELECT 1 FROM (
            SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags) - 2), '><')) as TagValue
        ) t WHERE t.TagValue = ta.TagName
    )
    LEFT JOIN QualityPosts qa ON pa.PostId = qa.PostId
)
SELECT 
    f.UserId,
    f.DisplayName,
    f.Reputation,
    f.ReputationTier,
    f.PostCount,
    f.CommentCount,
    f.BadgeCount,
    f.AvgPostScore,
    f.QuestionCount,
    f.AnswerCount,
    CAST(ROUND(f.AcceptanceRate, 2) AS DECIMAL(10,2)) as AcceptanceRate,
    CAST(ROUND(f.AnswerPercentage, 2) AS DECIMAL(10,2)) as AnswerPercentage,
    f.PostId,
    f.Title,
    f.Score,
    f.ViewCount,
    f.PostCommentCount,
    f.PostAnswerCount,
    f.AgeInDays,
    f.ViewCategory,
    f.En EngagementStatus,
    f.Status,
    f.QualityCategory,
    f.TagName,
    f.TagUsage,
    f.Popularity,
    f.PostClassification,
    f.UserPostRanking,
    CAST(ROUND(f.ScoreCommentProduct, 2) AS DECIMAL(10,2)) as ScoreCommentProduct,
    CAST(ROUND(f.CommentsPerAnswer, 2) AS DECIMAL(10,2)) as CommentsPerAnswer,
    f.PostAgeCategory,
    f.ScoreChange,
    CAST(ROUND(f.UserPostScoreWeight, 2) AS DECIMAL(10,2)) as UserPostScoreWeight,
    f.EngagementLevel,
    f.OverallRank,
    f.TierRank
FROM FinalAnalysis f
WHERE f.Score > 0 AND f.ViewCount > 0
ORDER BY 
    f.Reputation DESC,
    f.Score DESC,
    f.OverallRank ASC,
    f.TierRank ASC
LIMIT 10000;