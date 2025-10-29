-- {"query": "7824.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2976} 
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
        COUNT(DISTINCT c.Id) as Comments,
        COUNT(DISTINCT b.Id) as Badges,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        DATEDIFF(CURRENT_TIMESTAMP, u.CreationDate) as AccountAgeDays,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Elite'
            WHEN u.Reputation >= 1000 THEN 'Veteran'
            WHEN u.Reputation >= 100 THEN 'Regular'
            ELSE 'Newbie'
        END as ReputationTier,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as QuestionScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as AnswerScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) as QuestionViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE 0 END), 0) as AnswerViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
RankedUsers AS (
    SELECT *,
        ROW_NUMBER() OVER (ORDER BY QuestionScore DESC, AnswerScore DESC) as ScoreRank,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC) as PostRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank
    FROM UserActivityStats
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        COALESCE(p.ViewCount, 0) as WikiViews,
        p.Score as WikiScore,
        p.CreationDate as WikiCreationDate,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate) as VersionOrder,
        CASE 
            WHEN p.PostTypeId = 5 THEN 'Wiki'
            WHEN p.PostTypeId = 4 THEN 'Excerpt'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            WHEN t.Count > 10 THEN 'Niche'
            ELSE 'Rare'
        END as PopularityLevel
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id OR t.ExcerptPostId = p.Id
    WHERE t.TagName IS NOT NULL
),
PostComplexity AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        LENGTH(p.Body) as BodyLength,
        LENGTH(p.Title) as TitleLength,
        CASE 
            WHEN LENGTH(p.Title) > 50 THEN 'Long Title'
            WHEN LENGTH(p.Title) > 25 THEN 'Medium Title'
            ELSE 'Short Title'
        END as TitleLengthCategory,
        CASE 
            WHEN LENGTH(p.Body) > 1000 THEN 'Long Body'
            WHEN LENGTH(p.Body) > 500 THEN 'Medium Body'
            ELSE 'Short Body'
        END as BodyLengthCategory,
        CASE 
            WHEN p.CommentCount > 10 THEN 'Highly Commented'
            WHEN p.CommentCount > 5 THEN 'Moderately Commented'
            ELSE 'Low Commented'
        END as CommentLevel,
        CASE 
            WHEN p.AnswerCount > 10 THEN 'Highly Answered'
            WHEN p.AnswerCount > 5 THEN 'Moderately Answered'
            ELSE 'Low Answered'
        END as AnswerLevel,
        p.CreationDate,
        DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) as AgeDays,
        p.OwnerUserId,
        COALESCE(p.ParentId, p.Id) as ThreadRootId,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.CreationDate) as AnswerOrder
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserPostInteractions AS (
    SELECT 
        pu.UserId,
        pu.PostId,
        pu.CreationDate as VoteDate,
        v.VoteTypeId,
        CASE 
            WHEN v.VoteTypeId IN (2, 3) THEN 'Voted'
            ELSE 'Other'
        END as VoteType,
        ROW_NUMBER() OVER (PARTITION BY pu.UserId, pu.PostId ORDER BY pu.CreationDate) as VoteSequence
    FROM Posts pu
    JOIN Votes v ON pu.Id = v.PostId
    WHERE v.VoteTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16)
),
DetailedPostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.AnswerCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        pa.QuestionScore,
        pa.AnswerScore,
        pa.QuestionViews,
        pa.AnswerViews,
        pa.TotalPosts,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            WHEN p.PostTypeId = 1 THEN 'Unanswered'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as ThreadStatus,
        CASE 
            WHEN p.Score > 0 THEN 'Positive'
            WHEN p.Score < 0 THEN 'Negative'
            ELSE 'Neutral'
        END as ScoreCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 100 THEN 'Popular'
            WHEN p.ViewCount > 10 THEN 'Noticeable'
            ELSE 'Obscure'
        END as ViewCategory
    FROM Posts p
    JOIN (
        SELECT 
            OwnerUserId,
            SUM(CASE WHEN PostTypeId = 1 THEN Score ELSE 0 END) as QuestionScore,
            SUM(CASE WHEN PostTypeId = 2 THEN Score ELSE 0 END) as AnswerScore,
            SUM(CASE WHEN PostTypeId = 1 THEN ViewCount ELSE 0 END) as QuestionViews,
            SUM(CASE WHEN PostTypeId = 2 THEN ViewCount ELSE 0 END) as AnswerViews,
            COUNT(*) as TotalPosts
        FROM Posts
        GROUP BY OwnerUserId
    ) pa ON p.OwnerUserId = pa.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)
)
SELECT 
    'Performance Benchmark Query Results' as QueryDescription,
    COUNT(*) as TotalRecords,
    (SELECT COUNT(*) FROM Users) as TotalUsers,
    (SELECT COUNT(*) FROM Posts) as TotalPosts,
    (SELECT COUNT(*) FROM Tags) as TotalTags,
    (SELECT COUNT(*) FROM Comments) as TotalComments,
    (SELECT COUNT(*) FROM Votes) as TotalVotes,
    (SELECT COUNT(*) FROM Badges) as TotalBadges,
    COALESCE(SUM(CASE WHEN r.UserId IS NOT NULL THEN 1 ELSE 0 END), 0) as ActiveUsers,
    COUNT(DISTINCT CASE WHEN ra.ReputationTier = 'Elite' THEN ra.UserId END) as EliteUsers,
    COUNT(DISTINCT CASE WHEN ra.ReputationTier = 'Veteran' THEN ra.UserId END) as VeteranUsers,
    COUNT(DISTINCT CASE WHEN ra.ReputationTier = 'Regular' THEN ra.UserId END) as RegularUsers,
    COUNT(DISTINCT CASE WHEN ra.ReputationTier = 'Newbie' THEN ra.UserId END) as NewbieUsers,
    AVG(CASE WHEN ra.QuestionScore IS NOT NULL THEN ra.QuestionScore ELSE 0 END) as AvgQuestionScore,
    AVG(CASE WHEN ra.AnswerScore IS NOT NULL THEN ra.AnswerScore ELSE 0 END) as AvgAnswerScore,
    SUM(CASE WHEN ta.PopularityLevel = 'Popular' THEN 1 ELSE 0 END) as PopularTags,
    SUM(CASE WHEN ta.PopularityLevel = 'Moderate' THEN 1 ELSE 0 END) as ModerateTags,
    SUM(CASE WHEN ta.PopularityLevel = 'Niche' THEN 1 ELSE 0 END) as NicheTags,
    SUM(CASE WHEN ta.PopularityLevel = 'Rare' THEN 1 ELSE 0 END) as RareTags,
    AVG(CASE WHEN p.AgeDays IS NOT NULL THEN p.AgeDays ELSE 0 END) as AvgPostAgeDays,
    COUNT(DISTINCT CASE WHEN p.ThreadStatus = 'Answered' THEN p.Id END) as AnsweredQuestions,
    COUNT(DISTINCT CASE WHEN p.ThreadStatus = 'Unanswered' THEN p.Id END) as UnansweredQuestions,
    COUNT(DISTINCT CASE WHEN p.ScoreCategory = 'Positive' THEN p.Id END) as PositiveScorePosts,
    COUNT(DISTINCT CASE WHEN p.ScoreCategory = 'Negative' THEN p.Id END) as NegativeScorePosts,
    COUNT(DISTINCT CASE WHEN p.ViewCategory = 'Viral' THEN p.Id END) as ViralPosts,
    COUNT(DISTINCT CASE WHEN p.ViewCategory = 'Popular' THEN p.Id END) as PopularPosts,
    COUNT(DISTINCT CASE WHEN p.ViewCategory = 'Noticeable' THEN p.Id END) as NoticeablePosts,
    COUNT(DISTINCT CASE WHEN p.ViewCategory = 'Obscure' THEN p.Id END) as ObscurePosts,
    MAX(CASE WHEN ra.RepRank = 1 THEN ra.Reputation ELSE 0 END) as TopReputation,
    MAX(CASE WHEN ra.ScoreRank = 1 THEN ra.QuestionScore ELSE 0 END) as TopQuestionScore,
    MAX(CASE WHEN ra.PostRank = 1 THEN ra.TotalPosts ELSE 0 END) as MostActiveUserPostCount,
    AVG(CASE WHEN p.AnswerCount > 0 THEN p.AnswerCount ELSE 0 END) as AvgAnswerCount,
    AVG(CASE WHEN p.CommentCount > 0 THEN p.CommentCount ELSE 0 END) as AvgCommentCount,
    COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) THEN p.Id END) as PostsWithUpvotes,
    COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) THEN p.Id END) as PostsWithDownvotes,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as TotalQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as TotalAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as TotalWikis,
    COALESCE(SUM(CASE WHEN p.Score >= 10 THEN 1 ELSE 0 END), 0) as HighScorePosts,
    COALESCE(SUM(CASE WHEN p.Score <= -1 THEN 1 ELSE 0 END), 0) as LowScorePosts,
    COUNT(DISTINCT CASE WHEN p.ViewCount > 100 THEN p.Id END) as HighViewPosts,
    COUNT(DISTINCT CASE WHEN p.CommentCount > 20 THEN p.Id END) as HighCommentPosts,
    COUNT(DISTINCT CASE WHEN pa.ThreadStatus = 'Answered' THEN pa.Id END) as AnsweredThreadCount,
    COUNT(DISTINCT CASE WHEN pa.ThreadStatus = 'Unanswered' THEN pa.Id END) as UnansweredThreadCount,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Posts pp WHERE pp.OwnerUserId = u.Id AND pp.PostTypeId = 1) THEN 1 END) DESC) as QuestionAuthorRank,
    DENSE_RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM Posts pp WHERE pp.OwnerUserId = u.Id AND pp.PostTypeId = 2) THEN 1 END) DESC) as AnswerAuthorRank
FROM Users u
FULL OUTER JOIN RankedUsers ra ON u.Id = ra.UserId
FULL OUTER JOIN TagAnalysis ta ON 1 = 1
FULL OUTER JOIN PostComplexity p ON 1 = 1
FULL OUTER JOIN DetailedPostAnalysis pa ON 1 = 1
WHERE u.Id IS NOT NULL OR ra.UserId IS NOT NULL OR ta.TagName IS NOT NULL OR p.Id IS NOT NULL OR pa.Id IS NOT NULL
GROUP BY 
    ra.ReputationTier,
    ta.PopularityLevel,
    p.ThreadStatus,
    p.ScoreCategory,
    p.ViewCategory
HAVING 
    COUNT(*) > 0
ORDER BY 
    COUNT(*) DESC,
    ra.Reputation DESC,
    ta.Count DESC,
    p.Score DESC,
    p.ViewCount DESC
LIMIT 1000;