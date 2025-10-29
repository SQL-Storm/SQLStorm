-- {"query": "7967.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3976} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        COUNT(DISTINCT v.Id) as Votes,
        MAX(p.CreationDate) as LastPostDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Master'
            WHEN u.Reputation >= 1000 THEN 'Expert'
            WHEN u.Reputation >= 100 THEN 'Novice'
            ELSE 'Beginner'
        END as ReputationLevel,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
        AVG(COALESCE(p.Score, 0)) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as CommonTags,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentQuestions,
        (SELECT COUNT(*) FROM Posts WHERE OwnerUserId = u.Id AND PostTypeId = 2 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopPerformers AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        Questions,
        Answers,
        Comments,
        Badges,
        Votes,
        LastPostDate,
        AccountAgeDays,
        ReputationLevel,
        TotalQuestionScore,
        TotalAnswerScore,
        AvgPostScore,
        RecentQuestions,
        RecentAnswers,
        ROW_NUMBER() OVER (ORDER BY TotalQuestionScore DESC, TotalAnswerScore DESC, Reputation DESC) as RankByScore,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, Reputation DESC) as RankByActivity,
        RANK() OVER (ORDER BY AccountAgeDays ASC) as RankBySeniority,
        PERCENT_RANK() OVER (ORDER BY Reputation) as ReputationPercentile,
        NTILE(4) OVER (ORDER BY Reputation) as ReputationQuartile,
        CASE 
            WHEN TotalPosts > 0 AND (Questions * 100.0 / TotalPosts) > 70 THEN 'Question Focused'
            WHEN TotalPosts > 0 AND (Answers * 100.0 / TotalPosts) > 70 THEN 'Answer Focused'
            ELSE 'Balanced'
        END as ContributionStyle
    FROM UserActivityStats
),
RecentActivity AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as Author,
        p.OwnerUserId,
        p.PostTypeId,
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
        END as PostType,
        ABS(p.ViewCount - (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1)) as ViewCountDeviation,
        CASE 
            WHEN p.ViewCount > (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 1.5 THEN 'High'
            WHEN p.ViewCount < (SELECT AVG(ViewCount) FROM Posts WHERE PostTypeId = 1) * 0.5 THEN 'Low'
            ELSE 'Normal'
        END as ViewCountCategory,
        p.Tags,
        p.CommentCount,
        p.FavoriteCount,
        IIF(p.AcceptedAnswerId IS NOT NULL, 'Has Accepted Answer', 'No Accepted Answer') as AnswerStatus,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeInDays,
        DATEDIFF(p.LastActivityDate, p.CreationDate) as ActivityDurationDays,
        CASE 
            WHEN p.CommentCount = 0 AND p.FavoriteCount = 0 THEN 'Low Engagement'
            WHEN p.CommentCount > 5 OR p.FavoriteCount > 5 THEN 'High Engagement'
            ELSE 'Medium Engagement'
        END as EngagementLevel
    FROM Posts p
    INNER JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATEADD(MONTH, -6, CURRENT_TIMESTAMP)
    AND p.PostTypeId IN (1, 2)
    AND p.Score >= 0
),
UserEngagementMetrics AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT v.Id) as Votes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId IN (1, 2, 3) THEN v.Id END) as VoteActivity,
        COUNT(DISTINCT CASE WHEN c.Id IS NOT NULL THEN c.Id END) as CommentActivity,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpvoteRatio,
        AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownvoteRatio,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 4 THEN v.Id END) as OffensiveReports,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
        MAX(CASE 
            WHEN v.VoteTypeId IN (2) AND p.PostTypeId = 1 THEN v.Id
            WHEN v.VoteTypeId = 2 AND p.PostTypeId = 2 THEN v.Id
            ELSE NULL 
        END) as LastUpvote,
        MAX(CASE 
            WHEN v.VoteTypeId IN (3) AND p.PostTypeId = 1 THEN v.Id
            WHEN v.VoteTypeId = 3 AND p.PostTypeId = 2 THEN v.Id
            ELSE NULL 
        END) as LastDownvote,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 THEN 0
            ELSE COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 AND p.PostTypeId = 1 THEN v.Id END) * 100.0 / 
                 COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
        END as QuestionUpvotePercentage,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 THEN 0
            ELSE COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 AND p.PostTypeId = 2 THEN v.Id END) * 100.0 / 
                 COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)
        END as AnswerUpvotePercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName
),
CombinedMetrics AS (
    SELECT 
        tp.UserId,
        tp.DisplayName,
        tp.Reputation,
        tp.TotalPosts,
        tp.Questions,
        tp.Answers,
        tp.Comments,
        tp.Badges,
        tp.Votes,
        tp.LastPostDate,
        tp.AccountAgeDays,
        tp.ReputationLevel,
        tp.TotalQuestionScore,
        tp.TotalAnswerScore,
        tp.AvgPostScore,
        tp.RecentQuestions,
        tp.RecentAnswers,
        tp.RankByScore,
        tp.RankByActivity,
        tp.RankBySeniority,
        tp.ReputationPercentile,
        tp.ReputationQuartile,
        tp.ContributionStyle,
        uem.TotalPosts as UserTotalPosts,
        uem.Questions as UserQuestions,
        uem.Answers as UserAnswers,
        uem.Comments as UserComments,
        uem.Votes as UserVotes,
        uem.VoteActivity,
        uem.CommentActivity,
        uem.UpvoteRatio,
        uem.DownvoteRatio,
        uem.OffensiveReports,
        uem.Favorites,
        uem.LastUpvote,
        uem.LastDownvote,
        uem.QuestionUpvotePercentage,
        uem.AnswerUpvotePercentage,
        ra.PostId,
        ra.Title,
        ra.Score,
        ra.ViewCount,
        ra.CreationDate,
        ra.PostType,
        ra.ViewCountDeviation,
        ra.ViewCountCategory,
        ra.Tags,
        ra.CommentCount,
        ra.FavoriteCount,
        ra.AnswerStatus,
        ra.AgeInDays,
        ra.ActivityDurationDays,
        ra.EngagementLevel,
        CASE 
            WHEN tp.Reputation > 1000 AND ra.AgeInDays < 30 THEN 'Recent Active High Rep'
            WHEN tp.Reputation > 1000 AND ra.AgeInDays >= 30 THEN 'Veteran High Rep'
            WHEN tp.Reputation <= 1000 AND ra.AgeInDays < 30 THEN 'Recent Active Low Rep'
            ELSE 'Veteran Low Rep'
        END as UserPostCategory,
        CASE 
            WHEN tp.TotalPosts > 100 THEN 'Elite Contributor'
            WHEN tp.TotalPosts > 50 THEN 'High Contributor'
            WHEN tp.TotalPosts > 10 THEN 'Regular Contributor'
            ELSE 'Casual Contributor'
        END as ContributorTier,
        CASE 
            WHEN ra.Score > 100 AND ra.ViewCount > 1000 THEN 'Viral Post'
            WHEN ra.Score > 50 AND ra.ViewCount > 500 THEN 'Popular Post'
            WHEN ra.Score > 10 AND ra.ViewCount > 100 THEN 'Noticeable Post'
            WHEN ra.Score > 0 THEN 'Standard Post'
            ELSE 'Low Impact Post'
        END as PostImpact,
        CASE 
            WHEN ra.ViewCount > 10000 THEN 'Viral'
            WHEN ra.ViewCount > 1000 THEN 'Popular'
            WHEN ra.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Low Reach'
        END as PostReach,
        CASE 
            WHEN ra.CommentCount > 10 THEN 'High Comment Activity'
            WHEN ra.CommentCount > 5 THEN 'Medium Comment Activity'
            WHEN ra.CommentCount > 0 THEN 'Low Comment Activity'
            ELSE 'No Comments'
        END as CommentActivityLevel,
        CASE 
            WHEN ra.FavoriteCount > 10 THEN 'High Favorite Count'
            WHEN ra.FavoriteCount > 5 THEN 'Medium Favorite Count'
            WHEN ra.FavoriteCount > 0 THEN 'Low Favorite Count'
            ELSE 'No Favorites'
        END as FavoriteActivityLevel
    FROM TopPerformers tp
    INNER JOIN UserEngagementMetrics uem ON tp.UserId = uem.UserId
    LEFT JOIN RecentActivity ra ON tp.UserId = ra.OwnerUserId
    WHERE tp.UserId IN (SELECT UserId FROM RecentActivity GROUP BY UserId HAVING COUNT(*) > 0)
    UNION ALL
    SELECT 
        0 as UserId,
        'Overall Summary' as DisplayName,
        (SELECT AVG(Reputation) FROM Users WHERE Id > 0) as Reputation,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId IN (1,2)) as TotalPosts,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 1) as Questions,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 2) as Answers,
        (SELECT COUNT(*) FROM Comments WHERE Id > 0) as Comments,
        (SELECT COUNT(*) FROM Badges WHERE Id > 0) as Badges,
        (SELECT COUNT(*) FROM Votes WHERE Id > 0) as Votes,
        (SELECT MAX(CreationDate) FROM Users WHERE Id > 0) as LastPostDate,
        (SELECT AVG(DATEDIFF(CURRENT_TIMESTAMP, CreationDate)) FROM Users WHERE Id > 0) as AccountAgeDays,
        'Overall' as ReputationLevel,
        (SELECT SUM(Score) FROM Posts WHERE Id > 0 AND PostTypeId = 1) as TotalQuestionScore,
        (SELECT SUM(Score) FROM Posts WHERE Id > 0 AND PostTypeId = 2) as TotalAnswerScore,
        (SELECT AVG(Score) FROM Posts WHERE Id > 0) as AvgPostScore,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 1 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentQuestions,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 2 AND CreationDate >= DATEADD(YEAR, -1, CURRENT_TIMESTAMP)) as RecentAnswers,
        0 as RankByScore,
        0 as RankByActivity,
        0 as RankBySeniority,
        0 as ReputationPercentile,
        0 as ReputationQuartile,
        'Overall' as ContributionStyle,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId IN (1, 2)) as UserTotalPosts,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 1) as UserQuestions,
        (SELECT COUNT(*) FROM Posts WHERE Id > 0 AND PostTypeId = 2) as UserAnswers,
        (SELECT COUNT(*) FROM Comments WHERE Id > 0) as UserComments,
        (SELECT COUNT(*) FROM Votes WHERE Id > 0) as UserVotes,
        (SELECT COUNT(*) FROM Votes WHERE Id > 0 AND VoteTypeId IN (1,2,3)) as VoteActivity,
        (SELECT COUNT(*) FROM Comments WHERE Id > 0) as CommentActivity,
        (SELECT AVG(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) FROM Votes WHERE Id > 0) as UpvoteRatio,
        (SELECT AVG(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) FROM Votes WHERE Id > 0) as DownvoteRatio,
        (SELECT COUNT(*) FROM Votes WHERE Id > 0 AND VoteTypeId = 4) as OffensiveReports,
        (SELECT COUNT(*) FROM Votes WHERE Id > 0 AND VoteTypeId = 5) as Favorites,
        NULL as LastUpvote,
        NULL as LastDownvote,
        0 as QuestionUpvotePercentage,
        0 as AnswerUpvotePercentage,
        NULL as PostId,
        NULL as Title,
        0 as Score,
        0 as ViewCount,
        NULL as CreationDate,
        NULL as PostType,
        0 as ViewCountDeviation,
        NULL as ViewCountCategory,
        NULL as Tags,
        0 as CommentCount,
        0 as FavoriteCount,
        NULL as AnswerStatus,
        0 as AgeInDays,
        0 as ActivityDurationDays,
        NULL as EngagementLevel,
        NULL as UserPostCategory,
        'Summary' as ContributorTier,
        NULL as PostImpact,
        NULL as PostReach,
        NULL as CommentActivityLevel,
        NULL as FavoriteActivityLevel
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    TotalPosts,
    Questions,
    Answers,
    Comments,
    Badges,
    Votes,
    LastPostDate,
    AccountAgeDays,
    ReputationLevel,
    TotalQuestionScore,
    TotalAnswerScore,
    AvgPostScore,
    RecentQuestions,
    RecentAnswers,
    RankByScore,
    RankByActivity,
    RankBySeniority,
    ReputationPercentile,
    ReputationQuartile,
    ContributionStyle,
    UserTotalPosts,
    UserQuestions,
    UserAnswers,
    UserComments,
    UserVotes,
    VoteActivity,
    CommentActivity,
    UpvoteRatio,
    DownvoteRatio,
    OffensiveReports,
    Favorites,
    LastUpvote,
    LastDownvote,
    QuestionUpvotePercentage,
    AnswerUpvotePercentage,
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    PostType,
    ViewCountDeviation,
    ViewCountCategory,
    Tags,
    CommentCount,
    FavoriteCount,
    AnswerStatus,
    AgeInDays,
    ActivityDurationDays,
    EngagementLevel,
    UserPostCategory,
    ContributorTier,
    PostImpact,
    PostReach,
    CommentActivityLevel,
    FavoriteActivityLevel,
    CASE 
        WHEN Reputation > 10000 THEN 'Elite'
        WHEN Reputation > 1000 THEN 'Expert'
        WHEN Reputation > 100 THEN 'Intermediate'
        ELSE 'Beginner'
    END as OverallRank,
    CASE 
        WHEN OverallRank IN ('Elite', 'Expert') AND PostImpact IN ('Viral Post', 'Popular Post') THEN 'High Impact'
        WHEN OverallRank = 'Intermediate' AND PostImpact IN ('Popular Post', 'Noticeable Post') THEN 'Medium Impact'
        ELSE 'Low Impact'
    END as ImpactCategory,
    COUNT(*) OVER() as TotalRecords,
    ROW_NUMBER() OVER(ORDER BY Score DESC, ViewCount DESC) as ContentPopularityRank
FROM CombinedMetrics
WHERE UserId > 0
AND (PostId IS NOT NULL OR PostId IS NULL)
AND ReputationLevel IS NOT NULL
AND AgeInDays >= 0
AND AccountAgeDays >= 0
AND Score >= -100
ORDER BY 
    Reputation DESC,
    TotalPosts DESC,
    UserTotalPosts DESC,
    Score DESC,
    ViewCount DESC
LIMIT 10000;