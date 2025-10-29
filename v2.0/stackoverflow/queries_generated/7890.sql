-- {"query": "7890.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 3446} 
WITH UserActivityStats AS (
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
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        MAX(p.CreationDate) as LatestPostDate,
        MAX(c.CreationDate) as LatestCommentDate,
        MAX(b.Date) as LatestBadgeDate,
        COUNT(DISTINCT CASE WHEN p.Score > 0 THEN p.Id END) as PositiveScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) as NegativeScorePosts,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) as HighViewPosts,
        COUNT(DISTINCT CASE WHEN p.AnswerCount > 50 THEN p.Id END) as HighAnsweredQuestions,
        COUNT(DISTINCT CASE WHEN p.CommentCount > 100 THEN p.Id END) as HighCommentedPosts,
        COUNT(DISTINCT CASE WHEN p.FavoriteCount > 10 THEN p.Id END) as HighFavoritedPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as UserRank,
        RANK() OVER (ORDER BY Views DESC) as ViewRank,
        DENSE_RANK() OVER (ORDER BY UpVotes DESC) as UpVoteRank,
        NTILE(10) OVER (ORDER BY Reputation DESC) as ReputationTier,
        CASE 
            WHEN PostCount = 0 THEN 'Inactive'
            WHEN PostCount BETWEEN 1 AND 10 THEN 'Beginner'
            WHEN PostCount BETWEEN 11 AND 100 THEN 'Intermediate'
            WHEN PostCount BETWEEN 101 AND 1000 THEN 'Advanced'
            ELSE 'Expert'
        END as ActivityLevel,
        CASE 
            WHEN HighestScore > 1000 THEN 'Legendary'
            WHEN HighestScore > 500 THEN 'Master'
            WHEN HighestScore > 100 THEN 'Expert'
            WHEN HighestScore > 50 THEN 'Advanced'
            WHEN HighestScore > 10 THEN 'Intermediate'
            ELSE 'Beginner'
        END as SkillLevel
    FROM (
        SELECT 
            uas.*,
            MAX(p.Score) OVER (PARTITION BY uas.UserId) as HighestScore,
            MAX(p.CreationDate) OVER (PARTITION BY uas.UserId) as LatestPostDate
        FROM UserActivityStats uas
        LEFT JOIN Posts p ON uas.UserId = p.OwnerUserId
    ) ranked_data
),
PostEngagementMetrics AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Tags,
        COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '') as CleanTags,
        ARRAY(
            SELECT TRIM(tag) 
            FROM UNNEST(STRING_TO_ARRAY(COALESCE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), ''), '><')) as tag
        ) as TagArray,
        (SELECT COUNT(*) FROM Posts ps WHERE ps.ParentId = p.Id AND ps.PostTypeId = 2) as AnswerCountActual,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpvoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownvoteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCountActual,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Date >= p.CreationDate AND b.Date <= p.CreationDate + INTERVAL '30 days') as BadgeCountThisMonth,
        (SELECT AVG(Score) FROM Posts ps WHERE ps.OwnerUserId = p.OwnerUserId AND ps.CreationDate >= p.CreationDate - INTERVAL '7 days') as AvgWeeklyScore,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts ps WHERE ps.ParentId = p.Id AND ps.PostTypeId = 2 AND ps.Score > 0)
            ELSE 0 
        END as PositiveAnswers,
        CASE 
            WHEN p.PostTypeId = 1 THEN 
                (SELECT COUNT(*) FROM Posts ps WHERE ps.ParentId = p.Id AND ps.PostTypeId = 2 AND ps.Score < 0)
            ELSE 0 
        END as NegativeAnswers
    FROM Posts p
    JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= '2020-01-01'
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count >= 1000 THEN 'Viral'
            WHEN t.Count >= 500 THEN 'Popular'
            WHEN t.Count >= 100 THEN 'Common'
            WHEN t.Count >= 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel,
        AVG(p.Score) as AvgScoreForTag,
        COUNT(DISTINCT p.OwnerUserId) as UniqueAuthors,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
        AVG(p.ViewCount) as AvgViews,
        AVG(p.AnswerCount) as AvgAnswers,
        MAX(p.CreationDate) as LatestPostDate
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, t.IsModeratorOnly, t.IsRequired
)
SELECT 
    'Performance Benchmark Report' as ReportName,
    COUNT(*) as TotalUsers,
    COUNT(DISTINCT CASE WHEN ru.ActivityLevel = 'Expert' THEN ru.UserId END) as ExpertUsers,
    COUNT(DISTINCT CASE WHEN ru.ReputationTier = 1 THEN ru.UserId END) as TopTierUsers,
    COUNT(DISTINCT CASE WHEN pem.PostTypeId = 1 THEN pem.PostId END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN pem.PostTypeId = 2 THEN pem.PostId END) as AnswerCount,
    SUM(pem.Score) as TotalScore,
    AVG(pem.Score) as AverageScore,
    SUM(pem.ViewCount) as TotalViews,
    AVG(pem.ViewCount) as AverageViews,
    SUM(CASE WHEN pem.AnswerCount > 0 THEN pem.AnswerCount ELSE 0 END) as TotalAnswers,
    SUM(CASE WHEN pem.CommentCount > 0 THEN pem.CommentCount ELSE 0 END) as TotalComments,
    COUNT(DISTINCT COALESCE(pem.OwnerUserId, 0)) as UniqueAuthors,
    COUNT(DISTINCT CASE WHEN tm.PopularityLevel = 'Viral' THEN tm.TagName END) as ViralTags,
    COUNT(DISTINCT CASE WHEN tm.PopularityLevel = 'Popular' THEN tm.TagName END) as PopularTags,
    COUNT(DISTINCT CASE WHEN tm.PopularityLevel = 'Common' THEN tm.TagName END) as CommonTags,
    COUNT(DISTINCT CASE WHEN tm.PopularityLevel = 'Moderate' THEN tm.TagName END) as ModerateTags,
    COUNT(DISTINCT CASE WHEN tm.PopularityLevel = 'Rare' THEN tm.TagName END) as RareTags,
    COUNT(DISTINCT CASE WHEN pem.Score > 100 THEN pem.PostId END) as HighScorePosts,
    COUNT(DISTINCT CASE WHEN pem.ViewCount > 10000 THEN pem.PostId END) as VeryHighViewPosts,
    COUNT(DISTINCT CASE WHEN pem.AnswerCount > 100 THEN pem.PostId END) as HighlyAnsweredQuestions,
    COUNT(DISTINCT CASE WHEN pem.CommentCount > 500 THEN pem.PostId END) as HighlyCommentedPosts,
    COUNT(DISTINCT CASE WHEN pem.FavoriteCount > 50 THEN pem.PostId END) as HighlyFavoritedPosts,
    COUNT(DISTINCT CASE WHEN LENGTH(pem.Title) > 100 THEN pem.PostId END) as LongTitlePosts,
    COUNT(DISTINCT CASE WHEN LENGTH(pem.Title) < 20 THEN pem.PostId END) as ShortTitlePosts,
    COUNT(DISTINCT CASE WHEN LENGTH(pem.Tags) > 50 THEN pem.PostId END) as ManyTagsPosts,
    COUNT(DISTINCT CASE WHEN LENGTH(pem.Tags) < 20 THEN pem.PostId END) as FewTagsPosts,
    SUM(CASE WHEN pem.TagArray IS NOT NULL THEN ARRAY_LENGTH(pem.TagArray, 1) ELSE 0 END) as TotalTagCount,
    AVG(CASE WHEN pem.TagArray IS NOT NULL THEN ARRAY_LENGTH(pem.TagArray, 1) ELSE 0 END) as AverageTagsPerPost,
    COUNT(DISTINCT CASE WHEN LENGTH(pem.Title) > 50 AND pem.Score > 50 THEN pem.PostId END) as HighScoreLongTitlePosts,
    COUNT(DISTINCT CASE WHEN pem.ViewCount < 10 AND pem.Score > 100 THEN pem.PostId END) as HighScoreLowViewPosts,
    COUNT(DISTINCT CASE WHEN pem.AnswerCount > 20 AND pem.Score > 100 THEN pem.PostId END) as HighScoreManyAnswersPosts,
    COUNT(DISTINCT CASE WHEN pem.CommentCount > 100 AND pem.Score < 0 THEN pem.PostId END) as NegativeScoreManyCommentsPosts,
    COUNT(DISTINCT CASE WHEN pem.FavoriteCount > 20 AND pem.Score > 50 THEN pem.PostId END) as HighScoreHighFavoritesPosts,
    COUNT(DISTINCT CASE WHEN pem.Score > 100 AND pem.ViewCount > 1000 AND pem.AnswerCount > 10 THEN pem.PostId END) as ElitePostCount
FROM RankedUsers ru
FULL OUTER JOIN PostEngagementMetrics pem ON ru.UserId = pem.OwnerUserId
LEFT JOIN TagPopularity tm ON pem.Tags IS NOT NULL AND pem.Tags LIKE '%' || tm.TagName || '%'
WHERE ru.UserId IS NOT NULL OR pem.PostId IS NOT NULL OR tm.TagName IS NOT NULL
GROUP BY 
    'Performance Benchmark Report', 
    (SELECT COUNT(*) FROM Users WHERE CreationDate >= '2010-01-01'),
    (SELECT COUNT(DISTINCT UserId) FROM (
        SELECT UserId FROM Badges WHERE Date >= '2022-01-01'
        INTERSECT
        SELECT Id FROM Users WHERE CreationDate >= '2020-01-01'
    ) recent_badge_users),
    (SELECT COUNT(DISTINCT UserId) FROM Posts WHERE CreationDate >= '2020-01-01' AND OwnerUserId IS NOT NULL),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND PostTypeId = 1),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND PostTypeId = 2),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND Tags IS NOT NULL),
    (SELECT COUNT(DISTINCT Id) FROM Tags WHERE Count > 1000),
    (SELECT COUNT(DISTINCT Id) FROM Tags WHERE Count BETWEEN 500 AND 999),
    (SELECT COUNT(DISTINCT Id) FROM Tags WHERE Count BETWEEN 100 AND 499),
    (SELECT COUNT(DISTINCT Id) FROM Tags WHERE Count BETWEEN 10 AND 99),
    (SELECT COUNT(DISTINCT Id) FROM Tags WHERE Count < 10),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND Score > 100),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND ViewCount > 10000),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND AnswerCount > 100),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND CommentCount > 500),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND FavoriteCount > 50),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND LENGTH(Title) > 100),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND LENGTH(Title) < 20),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND LENGTH(Tags) > 50),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND LENGTH(Tags) < 20),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND (Tags LIKE '%<%' OR Tags LIKE '%>%')),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND Tags IS NOT NULL),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND LENGTH(Title) > 50 AND Score > 50),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND ViewCount < 10 AND Score > 100),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND AnswerCount > 20 AND Score > 100),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND CommentCount > 100 AND Score < 0),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND FavoriteCount > 20 AND Score > 50),
    (SELECT COUNT(DISTINCT Id) FROM Posts WHERE CreationDate >= '2020-01-01' AND Score > 100 AND ViewCount > 1000 AND AnswerCount > 10)
HAVING 
    COUNT(*) > 0
ORDER BY 
    TotalUsers DESC,
    QuestionCount DESC,
    AnswerCount DESC,
    TotalScore DESC
LIMIT 1000000;