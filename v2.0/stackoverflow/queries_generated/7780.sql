-- {"query": "7780.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2576} 
WITH UserStats AS (
    SELECT 
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.AccountId,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        COALESCE(SUM(p.Score), 0) as TotalScore,
        COALESCE(SUM(p.ViewCount), 0) as TotalViews,
        MAX(p.CreationDate) as LatestPostDate,
        MAX(u.CreationDate) as UserCreationDate,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeDays,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN 1 ELSE 0 END as HasWebsite,
        CASE WHEN u.Location IS NOT NULL AND u.Location != '' THEN 1 ELSE 0 END as HasLocation,
        CASE WHEN u.AboutMe IS NOT NULL AND LEN(u.AboutMe) > 10 THEN 1 ELSE 0 END as HasBio,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        NTILE(10) OVER (ORDER BY u.Reputation DESC) as ReputationDecile
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0 AND u.AccountId > 0
    GROUP BY u.Id, u.Reputation, u.DisplayName, u.Views, u.UpVotes, u.DownVotes, u.AccountId, u.WebsiteUrl, u.Location, u.AboutMe, u.CreationDate
),
TopQuestions AS (
    SELECT 
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) as PopularityRank,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM STRING_SPLIT(SUBSTRING(p.Tags, 2, LEN(p.Tags)-2), '><'))
            ELSE 0 
        END as TagCount,
        CASE 
            WHEN p.CreationDate >= DATEADD(month, -3, GETDATE()) THEN 'Recent'
            WHEN p.CreationDate >= DATEADD(month, -12, GETDATE()) THEN 'RecentYear'
            ELSE 'Old'
        END as PostAgeGroup
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Score > 10 
      AND p.ViewCount > 100
      AND p.CreationDate >= DATEADD(year, -2, GETDATE())
),
UserPostActivity AS (
    SELECT 
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Content Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Moderation Action'
            ELSE 'Other'
        END as ActionCategory,
        CASE 
            WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND LEN(ph.Comment) > 0 THEN 
                CAST(ph.Comment AS int)
            ELSE NULL 
        END as CloseReasonId
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL 
      AND ph.CreationDate >= DATEADD(month, -6, GETDATE())
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) as TagRank,
        LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as PrevTagCount,
        t.Count - LAG(t.Count, 1) OVER (ORDER BY t.Count DESC) as CountDiff
    FROM Tags t
    WHERE t.Count > 10
),
UserPerformance AS (
    SELECT 
        us.Id as UserId,
        us.Reputation,
        us.DisplayName,
        us.ReputationRank,
        us.ReputationDecile,
        us.PostCount,
        us.QuestionCount,
        us.AnswerCount,
        us.TotalScore,
        us.TotalViews,
        us.AccountAgeDays,
        us.HasWebsite,
        us.HasLocation,
        us.HasBio,
        CASE 
            WHEN us.Reputation > 10000 THEN 'Superuser'
            WHEN us.Reputation > 5000 THEN 'Expert'
            WHEN us.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as UserLevel,
        CASE 
            WHEN us.QuestionCount > 100 AND us.AnswerCount > 500 THEN 'Active Q&A Contributor'
            WHEN us.QuestionCount > 50 AND us.AnswerCount < 100 THEN 'Question Focused'
            WHEN us.QuestionCount < 10 AND us.AnswerCount > 100 THEN 'Answer Focused'
            ELSE 'Casual Contributor'
        END as ContributionStyle,
        us.PostCount * 1.0 / NULLIF(us.AccountAgeDays, 0) as DailyPostRate,
        (us.UpVotes * 1.0 / NULLIF(us.UpVotes + us.DownVotes, 0)) * 100 as UpvoteRatio
    FROM UserStats us
    WHERE us.PostCount > 0
),
CombinedAnalysis AS (
    SELECT 
        up.UserId,
        up.Reputation,
        up.DisplayName,
        up.UserLevel,
        up.ContributionStyle,
        up.PostCount,
        up.QuestionCount,
        up.AnswerCount,
        up.TotalScore,
        up.TotalViews,
        up.DailyPostRate,
        up.UpvoteRatio,
        COALESCE(MAX(ta.Count), 0) as MaxTagCount,
        COALESCE(SUM(CASE WHEN ta.TagName IS NOT NULL THEN 1 ELSE 0 END), 0) as TaggedPostCount,
        COUNT(DISTINCT upa.PostId) as EditActivityCount,
        COUNT(DISTINCT CASE WHEN upa.ActionCategory = 'Title/Tag Edit' THEN upa.PostId END) as TitleTagEditCount,
        COUNT(DISTINCT CASE WHEN upa.ActionCategory = 'Content Edit' THEN upa.PostId END) as ContentEditCount,
        COUNT(DISTINCT CASE WHEN upa.ActionCategory = 'Moderation Action' THEN upa.PostId END) as ModerationActionCount,
        COUNT(DISTINCT CASE WHEN upa.PostHistoryTypeId = 10 THEN upa.PostId END) as CloseActionCount,
        STRING_AGG(
            CASE 
                WHEN upa.ActionCategory IN ('Title/Tag Edit', 'Content Edit') THEN 
                    CONCAT(upa.ActionCategory, ': ', LEFT(upa.Comment, 50), '...') 
                ELSE NULL 
            END, 
            '; '
        ) as RecentEdits,
        STRING_AGG(
            CASE 
                WHEN upa.ActionCategory IN ('Moderation Action', 'Title/Tag Edit', 'Content Edit') THEN 
                    CONCAT(upa.ActionCategory, ' on ', upa.PostId) 
                ELSE NULL 
            END, 
            ', '
        ) as ActionSummary
    FROM UserPerformance up
    LEFT JOIN UserPostActivity upa ON up.UserId = upa.UserId
    LEFT JOIN Tags ta ON ta.TagName IN (
        SELECT value FROM STRING_SPLIT(
            CASE 
                WHEN upa.Text IS NOT NULL THEN upa.Text
                ELSE ''
            END, 
            '><'
        )
        WHERE LEFT(value, 1) = '<'
    )
    GROUP BY 
        up.UserId, up.Reputation, up.DisplayName, up.UserLevel, 
        up.ContributionStyle, up.PostCount, up.QuestionCount, 
        up.AnswerCount, up.TotalScore, up.TotalViews, 
        up.DailyPostRate, up.UpvoteRatio
),
TopPerformers AS (
    SELECT TOP 100
        ca.UserId,
        ca.Reputation,
        ca.DisplayName,
        ca.UserLevel,
        ca.ContributionStyle,
        ca.PostCount,
        ca.QuestionCount,
        ca.AnswerCount,
        ca.TotalScore,
        ca.TotalViews,
        ca.DailyPostRate,
        ca.UpvoteRatio,
        ca.MaxTagCount,
        ca.TaggedPostCount,
        ca.EditActivityCount,
        ca.TitleTagEditCount,
        ca.ContentEditCount,
        ca.ModerationActionCount,
        ca.CloseActionCount,
        ca.RecentEdits,
        ca.ActionSummary,
        ROW_NUMBER() OVER (ORDER BY ca.TotalScore DESC, ca.PostCount DESC) as OverallRank
    FROM CombinedAnalysis ca
    WHERE ca.PostCount > 50
      AND ca.Reputation > 500
)
SELECT 
    tp.UserId,
    tp.Reputation,
    tp.DisplayName,
    tp.UserLevel,
    tp.ContributionStyle,
    tp.PostCount,
    tp.QuestionCount,
    tp.AnswerCount,
    tp.TotalScore,
    tp.TotalViews,
    tp.DailyPostRate,
    tp.UpvoteRatio,
    tp.MaxTagCount,
    tp.TaggedPostCount,
    tp.EditActivityCount,
    tp.TitleTagEditCount,
    tp.ContentEditCount,
    tp.ModerationActionCount,
    tp.CloseActionCount,
    tp.RecentEdits,
    tp.ActionSummary,
    tp.OverallRank,
    CASE 
        WHEN tp.UserLevel = 'Superuser' AND tp.Reputation > 20000 THEN 'Elite Contributor'
        WHEN tp.UserLevel IN ('Expert', 'Superuser') AND tp.PostCount > 200 THEN 'High Performer'
        WHEN tp.TotalScore > 5000 AND tp.Reputation > 10000 THEN 'Top Performer'
        ELSE 'Regular Contributor'
    END as PerformanceCategory,
    CAST(NULLIF(tp.TotalScore * 1.0 / NULLIF(tp.TotalViews, 0), 0) AS DECIMAL(10,2)) as ScorePerViewRatio,
    CASE 
        WHEN tp.TotalViews > 10000 THEN 'High Visibility'
        WHEN tp.TotalViews > 1000 THEN 'Moderate Visibility'
        ELSE 'Low Visibility'
    END as VisibilityLevel,
    CASE 
        WHEN tp.DailyPostRate > 0.5 THEN 'High Activity'
        WHEN tp.DailyPostRate > 0.1 THEN 'Moderate Activity'
        ELSE 'Low Activity'
    END as ActivityLevel,
    RANK() OVER (ORDER BY tp.DailyPostRate DESC) as DailyActivityRank,
    DENSE_RANK() OVER (ORDER BY tp.Reputation DESC) as ReputationRank,
    COUNT(*) OVER () as TotalContributors,
    (tp.TaggedPostCount * 100.0) / NULLIF(tp.PostCount, 0) as TaggingEfficiency
FROM TopPerformers tp
WHERE tp.UserId IN (
    SELECT DISTINCT UserId 
    FROM UserPostActivity upa 
    WHERE upa.ActionCategory IN ('Title/Tag Edit', 'Content Edit')
)
ORDER BY tp.TotalScore DESC, tp.PostCount DESC, tp.Reputation DESC;