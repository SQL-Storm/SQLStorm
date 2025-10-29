-- {"query": "7574.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2881} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
        MAX(p.CreationDate) as LastPostDate,
        AVG(CAST(p.ViewCount AS FLOAT)) as AvgViews,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ' | ') as AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalQuestionScore,
        TotalAnswerScore,
        LastPostDate,
        AvgViews,
        AllTags,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC) as RankByQuestions,
        ROW_NUMBER() OVER (ORDER BY TotalAnswerScore DESC) as RankByAnswers,
        CASE 
            WHEN TotalPosts > 0 THEN (TotalAnswerScore * 1.0 / TotalPosts)
            ELSE 0 
        END as AvgScorePerPost
    FROM UserPostStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        p.Title as ExcerptTitle,
        CASE 
            WHEN t.ExcerptPostId IS NOT NULL THEN 
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.Tags LIKE '%' || t.TagName || '%')
            ELSE 0
        END as UsageCount,
        CASE 
            WHEN t.WikiPostId IS NOT NULL THEN 
                (SELECT COUNT(*) FROM Posts p3 WHERE p3.Id = t.WikiPostId AND p3.PostTypeId = 5)
            ELSE 0 
        END as WikiExists
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.TagName IS NOT NULL
),
UserBadges AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(b.Id) as TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) as GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) as SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) as BronzeBadges,
        STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
        MIN(b.Date) as FirstBadgeDate,
        MAX(b.Date) as LastBadgeDate,
        AVG(DATEDIFF(day, b.Date, GETDATE())) as AvgDaysSinceBadge
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName
),
ComplexPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN (SELECT Title FROM Posts WHERE Id = p.ParentId)
            ELSE NULL 
        END as ParentTitle,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 
                (SELECT Score FROM Posts WHERE Id = p.AcceptedAnswerId)
            ELSE 0 
        END as AcceptedAnswerScore,
        CASE 
            WHEN p.ParentId IS NOT NULL AND p.PostTypeId = 2 THEN 
                (SELECT Score FROM Posts WHERE Id = p.ParentId)
            ELSE 0 
        END as ParentScore,
        CASE 
            WHEN p.Tags IS NOT NULL THEN 
                (SELECT COUNT(*) FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.Score > 0 THEN 
                (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
            ELSE 0 
        END as Upvotes,
        CASE 
            WHEN p.Score < 0 THEN 
                (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3)
            ELSE 0 
        END as Downvotes,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = p.Id AND p2.PostTypeId = 2)
            ELSE 0 
        END as AnswerCount,
        CASE 
            WHEN p.CommentCount > 0 THEN 
                (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id)
            ELSE 0 
        END as CommentCount,
        CASE 
            WHEN p.Title IS NOT NULL THEN 
                LENGTH(p.Title)
            ELSE 0 
        END as TitleLength,
        CASE 
            WHEN p.Body IS NOT NULL THEN 
                LENGTH(p.Body)
            ELSE 0 
        END as BodyLength,
        CASE 
            WHEN p.LastEditDate IS NOT NULL THEN 
                DATEDIFF(day, p.CreationDate, p.LastEditDate)
            ELSE 0 
        END as DaysSinceEdit,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END as IsClosed,
        CASE 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END as IsCommunityOwned,
        CASE 
            WHEN p.FavoriteCount > 0 THEN 1 ELSE 0 END as HasFavorites,
        CASE 
            WHEN p.OwnerUserId IS NOT NULL THEN 
                (SELECT Reputation FROM Users u WHERE u.Id = p.OwnerUserId)
            ELSE 0 
        END as OwnerReputation
    FROM Posts p
    WHERE p.Id IS NOT NULL
    AND (p.PostTypeId IN (1, 2) OR p.PostTypeId IN (3, 4, 5))
),
FilteredUsers AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.TotalPosts,
        tu.QuestionCount,
        tu.AnswerCount,
        tu.TotalQuestionScore,
        tu.TotalAnswerScore,
        tu.RankByQuestions,
        tu.RankByAnswers,
        tu.AvgScorePerPost,
        ub.TotalBadges,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.BadgeNames,
        COALESCE(ub.FirstBadgeDate, '1900-01-01') as FirstBadgeDate,
        COALESCE(ub.LastBadgeDate, '1900-01-01') as LastBadgeDate,
        COALESCE(ub.AvgDaysSinceBadge, 0) as AvgDaysSinceBadge
    FROM TopUsers tu
    LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
    WHERE tu.TotalPosts >= 100
),
FinalReport AS (
    SELECT 
        fu.UserId,
        fu.DisplayName,
        fu.Reputation,
        fu.TotalPosts,
        fu.QuestionCount,
        fu.AnswerCount,
        fu.TotalQuestionScore,
        fu.TotalAnswerScore,
        fu.RankByQuestions,
        fu.RankByAnswers,
        fu.AvgScorePerPost,
        fu.TotalBadges,
        fu.GoldBadges,
        fu.SilverBadges,
        fu.BronzeBadges,
        fu.BadgeNames,
        fu.FirstBadgeDate,
        fu.LastBadgeDate,
        fu.AvgDaysSinceBadge,
        ta.TagName,
        ta.TagCount,
        ta.UsageCount,
        ta.WikiExists,
        cp.ParentTitle,
        cp.AcceptedAnswerScore,
        cp.ParentScore,
        cp.TagCount as PostTagCount,
        cp.Upvotes,
        cp.Downvotes,
        cp.AnswerCount as PostAnswerCount,
        cp.CommentCount,
        cp.TitleLength,
        cp.BodyLength,
        cp.DaysSinceEdit,
        cp.IsClosed,
        cp.IsCommunityOwned,
        cp.HasFavorites,
        cp.OwnerReputation,
        CASE 
            WHEN fu.Reputation > 10000 THEN 'Elite'
            WHEN fu.Reputation > 5000 THEN 'Veteran'
            WHEN fu.Reputation > 1000 THEN 'Regular'
            WHEN fu.Reputation > 100 THEN 'Newbie'
            ELSE 'Novice'
        END as UserLevel,
        CASE 
            WHEN fu.TotalBadges > 50 THEN 'Master'
            WHEN fu.TotalBadges > 25 THEN 'Expert'
            WHEN fu.TotalBadges > 10 THEN 'Intermediate'
            WHEN fu.TotalBadges > 0 THEN 'Beginner'
            ELSE 'No Badge'
        END as BadgeLevel,
        CASE 
            WHEN cp.TitleLength > 200 THEN 'Long Title'
            WHEN cp.TitleLength > 100 THEN 'Medium Title' 
            ELSE 'Short Title'
        END as TitleCategory,
        CASE 
            WHEN cp.BodyLength > 10000 THEN 'Long Body'
            WHEN cp.BodyLength > 5000 THEN 'Medium Body'
            ELSE 'Short Body'
        END as BodyCategory,
        DATEDIFF(day, fu.FirstBadgeDate, '2024-01-01') as DaysSinceFirstBadge,
        ROW_NUMBER() OVER (PARTITION BY fu.UserId ORDER BY cp.CreationDate DESC) as PostRank
    FROM FilteredUsers fu
    LEFT JOIN TagAnalysis ta ON 1=1
    LEFT JOIN ComplexPosts cp ON fu.UserId = cp.OwnerUserId
    WHERE fu.UserId IS NOT NULL
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    QuestionCount,
    AnswerCount,
    TotalQuestionScore,
    TotalAnswerScore,
    RankByQuestions,
    RankByAnswers,
    AvgScorePerPost,
    TotalBadges,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    BadgeNames,
    FirstBadgeDate,
    LastBadgeDate,
    AvgDaysSinceBadge,
    TagName,
    TagCount,
    UsageCount,
    WikiExists,
    ParentTitle,
    AcceptedAnswerScore,
    ParentScore,
    PostTagCount,
    Upvotes,
    Downvotes,
    PostAnswerCount,
    CommentCount,
    TitleLength,
    BodyLength,
    DaysSinceEdit,
    IsClosed,
    IsCommunityOwned,
    HasFavorites,
    OwnerReputation,
    UserLevel,
    BadgeLevel,
    TitleCategory,
    BodyCategory,
    DaysSinceFirstBadge,
    PostRank,
    CASE 
        WHEN AVG(TotalPosts) OVER (ORDER BY UserId ROWS UNBOUNDED PRECEDING) > 100 THEN 
            'High Activity User'
        WHEN AVG(TotalPosts) OVER (ORDER BY UserId ROWS UNBOUNDED PRECEDING) > 50 THEN 
            'Medium Activity User'
        ELSE 'Low Activity User'
    END as ActivityLevel,
    MAX(TotalPosts) OVER (PARTITION BY UserId) as MaxPostsPerUser,
    MIN(TotalPosts) OVER (PARTITION BY UserId) as MinPostsPerUser,
    COUNT(*) OVER (PARTITION BY UserId) as PostCountPerUser,
    AVG(Reputation) OVER (ORDER BY UserId ROWS BETWEEN 5 PRECEDING AND 5 FOLLOWING) as ReputationMovingAverage,
    (SELECT AVG(TotalQuestionScore) FROM FinalReport f2 WHERE f2.UserId = FinalReport.UserId) as AvgQuestionScore,
    (SELECT AVG(TotalAnswerScore) FROM FinalReport f3 WHERE f3.UserId = FinalReport.UserId) as AvgAnswerScore,
    CASE 
        WHEN EXISTS (SELECT 1 FROM FinalReport f4 WHERE f4.UserId = FinalReport.UserId AND f4.IsClosed = 1) THEN 'Has Closed Posts'
        ELSE 'No Closed Posts'
    END as HasClosedPosts,
    CASE 
        WHEN EXISTS (SELECT 1 FROM FinalReport f5 WHERE f5.UserId = FinalReport.UserId AND f5.HasFavorites = 1) THEN 'Has Favorited Posts'
        ELSE 'No Favorited Posts'
    END as HasFavoritedPosts,
    CONCAT('User-', UserId) as UserIdentifier,
    (1.0 * TotalAnswerScore / NULLIF(TotalPosts, 0)) as ScorePerPost,
    (1.0 * GoldBadges / NULLIF(TotalBadges, 0)) as GoldBadgeRatio,
    (1.0 * SilverBadges / NULLIF(TotalBadges, 0)) as SilverBadgeRatio,
    (1.0 * BronzeBadges / NULLIF(TotalBadges, 0)) as BronzeBadgeRatio
FROM FinalReport
WHERE UserId IS NOT NULL
  AND (TotalPosts > 50 OR TotalBadges > 10)
  AND (TagName IS NOT NULL OR PostTagCount > 0)
  AND (LastBadgeDate IS NOT NULL OR FirstBadgeDate IS NOT NULL)
  AND (Reputation > 100 OR TotalQuestionScore > 100)
ORDER BY UserId, PostRank DESC
LIMIT 10000;