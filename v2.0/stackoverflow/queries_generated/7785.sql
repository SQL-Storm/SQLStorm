-- {"query": "7785.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2114} 
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
        AVG(p.Score) as AvgPostScore,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), ', ') as AllTags,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) 
            ELSE 0 
        END as QuestionCount,
        CASE 
            WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0 
            THEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) 
            ELSE 0 
        END as AnswerCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, PostCount DESC) as UserRank,
        RANK() OVER (ORDER BY AVGPostScore DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) as BadgeRank
    FROM UserStats
),
TopUsers AS (
    SELECT * FROM RankedUsers WHERE UserRank <= 100
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
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question' 
            WHEN p.PostTypeId = 2 THEN 'Answer' 
            ELSE 'Other' 
        END as PostType,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        CASE 
            WHEN p.ParentId IS NOT NULL THEN 'Answer' 
            ELSE 'Question' 
        END as Type,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END as HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END as IsClosed,
        DATEDIFF(day, p.CreationDate, COALESCE(p.LastActivityDate, p.CreationDate)) as DaysActive,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as NextScore,
        NTILE(4) OVER (ORDER BY p.Score) as ScoreQuartile,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as PostSequence,
        CAST(
            CASE 
                WHEN p.Title IS NOT NULL 
                THEN (LENGTH(p.Title) + LENGTH(p.Body)) / 2.0 
                ELSE 0 
            END AS DECIMAL(10,2)
        ) as ContentSize
    FROM Posts p
),
UserPostStats AS (
    SELECT 
        u.Id as UserId,
        SUM(pa.Score) as TotalScore,
        AVG(pa.Score) as AvgScore,
        MAX(pa.Score) as MaxScore,
        SUM(pa.ViewCount) as TotalViews,
        AVG(pa.ViewCount) as AvgViews,
        COUNT(pa.PostId) as PostCount,
        STRING_AGG(CONCAT(pa.Title, ' (', pa.Score, ')'), '; ') as TopPosts,
        STRING_AGG(pa.Tags, '; ') as AllPostTags,
        COUNT(DISTINCT CASE WHEN pa.HasAcceptedAnswer = 1 THEN pa.PostId END) as AcceptedPosts,
        COUNT(DISTINCT CASE WHEN pa.IsClosed = 1 THEN pa.PostId END) as ClosedPosts
    FROM Users u
    INNER JOIN PostAnalysis pa ON u.Id = pa.OwnerUserId
    GROUP BY u.Id
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.IsRequired = 1 THEN 'Required' 
            WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' 
            ELSE 'Public' 
        END as TagAccessibility,
        RANK() OVER (ORDER BY t.Count DESC) as TagRank
    FROM Tags t
    WHERE t.Count > 0
),
CommunityMetrics AS (
    SELECT 
        COUNT(DISTINCT u.Id) as ActiveUsers,
        COUNT(DISTINCT p.Id) as TotalPosts,
        COUNT(DISTINCT c.Id) as TotalComments,
        COUNT(DISTINCT b.Id) as TotalBadges,
        AVG(u.Reputation) as AvgReputation,
        MAX(u.Reputation) as MaxReputation,
        MIN(u.Reputation) as MinReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
)
SELECT 
    cu.UserRank,
    cu.DisplayName,
    cu.Reputation,
    cu.PostCount,
    cu.CommentCount,
    cu.BadgeCount,
    cu.AvgPostScore,
    cu.QuestionCount,
    cu.AnswerCount,
    ups.TotalScore,
    ups.AvgScore,
    ups.MaxScore,
    ups.TotalViews,
    ups.AvgViews,
    ups.AcceptedPosts,
    ups.ClosedPosts,
    CASE 
        WHEN cu.BadgeCount > 0 THEN 
            DENSE_RANK() OVER (ORDER BY cu.BadgeCount DESC)
        ELSE 0 
    END as BadgeRank,
    CASE 
        WHEN cu.Reputation > (SELECT AVG(Reputation) FROM Users) THEN 1 
        ELSE 0 
    END as AboveAvgReputation,
    CASE 
        WHEN cu.PostCount > (SELECT AVG(PostCount) FROM UserStats) THEN 1 
        ELSE 0 
    END as HighPoster,
    CASE 
        WHEN cu.ScoreRank <= 10 THEN 'Top Scorer' 
        WHEN cu.ScoreRank <= 50 THEN 'High Scorer' 
        ELSE 'Regular' 
    END as UserCategory,
    CASE 
        WHEN cu.BadgeCount > 50 THEN 'Veteran' 
        WHEN cu.BadgeCount > 20 THEN 'Experienced' 
        ELSE 'Beginner' 
    END as BadgeCategory,
    COALESCE(ups.TopPosts, 'No posts') as TopPosts,
    COALESCE(ups.AllPostTags, 'No tags') as AllTags,
    STRING_AGG(
        CASE 
            WHEN pa.Type = 'Question' THEN CAST(pa.PostId AS VARCHAR(10)) || ':' || pa.Title 
            ELSE NULL 
        END, 
        '; '
    ) as QuestionPosts,
    STRING_AGG(
        CASE 
            WHEN pa.Type = 'Answer' THEN CAST(pa.PostId AS VARCHAR(10)) || ':' || pa.Title 
            ELSE NULL 
        END, 
        '; '
    ) as AnswerPosts,
    CAST(
        (cu.QuestionCount * 100.0 / NULLIF(cu.PostCount, 0)) 
        AS DECIMAL(5,2)
    ) as QuestionPercentage,
    CAST(
        (cu.AnswerCount * 100.0 / NULLIF(cu.PostCount, 0)) 
        AS DECIMAL(5,2)
    ) as AnswerPercentage,
    DATEDIFF(day, cu.LastPostDate, GETDATE()) as DaysSinceLastPost,
    CASE 
        WHEN cu.Reputation > (SELECT AVG(Reputation) FROM Users) AND cu.PostCount > 10 THEN 'Active'
        WHEN cu.Reputation > 1000 AND cu.BadgeCount > 10 THEN 'Active' 
        ELSE 'Inactive' 
    END as ActivityStatus,
    (SELECT COUNT(*) FROM CommunityMetrics) as CommunitySize,
    (SELECT ActiveUsers FROM CommunityMetrics) as ActiveUsers,
    (SELECT TotalPosts FROM CommunityMetrics) as TotalPosts,
    (SELECT TotalComments FROM CommunityMetrics) as TotalComments,
    (SELECT TotalBadges FROM CommunityMetrics) as TotalBadges,
    CASE 
        WHEN cu.Reputation > 10000 THEN 'Elite' 
        WHEN cu.Reputation > 5000 THEN 'Expert' 
        WHEN cu.Reputation > 1000 THEN 'Advanced' 
        ELSE 'Newbie' 
    END as UserTier,
    'Benchmark Query Result' as QueryType
FROM TopUsers cu
LEFT JOIN UserPostStats ups ON cu.UserId = ups.UserId
LEFT JOIN PostAnalysis pa ON cu.UserId = pa.OwnerUserId
GROUP BY 
    cu.UserRank,
    cu.DisplayName,
    cu.Reputation,
    cu.PostCount,
    cu.CommentCount,
    cu.BadgeCount,
    cu.AvgPostScore,
    cu.QuestionCount,
    cu.AnswerCount,
    ups.TotalScore,
    ups.AvgScore,
    ups.MaxScore,
    ups.TotalViews,
    ups.AvgViews,
    ups.AcceptedPosts,
    ups.ClosedPosts,
    cu.LastPostDate,
    cu.ScoreRank,
    cu.BadgeRank
HAVING 
    COUNT(DISTINCT pa.PostId) > 0
ORDER BY 
    cu.Reputation DESC,
    cu.PostCount DESC,
    cu.BadgeCount DESC;