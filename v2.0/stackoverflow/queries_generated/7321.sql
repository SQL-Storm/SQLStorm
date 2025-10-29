-- {"query": "7321.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1943} 
WITH PostStats AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) as UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) as TotalUserPosts,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as AvgUserScore,
        CASE 
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN 'QuestionWithAnswers'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 1 AND p.AnswerCount = 0 THEN 'QuestionNoAnswers'
            ELSE 'Other'
        END as PostTypeCategory,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'HighlyViewed'
            WHEN p.ViewCount > 100 THEN 'ModeratelyViewed'
            WHEN p.ViewCount > 10 THEN 'LowViewed'
            ELSE 'VeryLowViewed'
        END as ViewCategory,
        DATEDIFF('day', p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COALESCE(SUM(ps.Score), 0) as TotalScore,
        COUNT(ps.PostId) as TotalPosts,
        AVG(ps.Score) as AvgPostScore,
        MAX(ps.CreationDate) as LastPostDate,
        COUNT(CASE WHEN ps.PostTypeId = 1 THEN 1 END) as QuestionCount,
        COUNT(CASE WHEN ps.PostTypeId = 2 THEN 1 END) as AnswerCount,
        COUNT(CASE WHEN ps.Score > 0 THEN 1 END) as PositiveScoreCount,
        COUNT(CASE WHEN ps.Score < 0 THEN 1 END) as NegativeScoreCount,
        COALESCE(COUNT(CASE WHEN ps.Score > 10 THEN 1 END), 0) as HighScorePosts
    FROM Users u
    LEFT JOIN PostStats ps ON u.Id = ps.OwnerUserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        ps.PostId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.Title,
        ps.Tags,
        ps.PostTypeCategory,
        ps.ViewCategory,
        ps.DaysSinceCreation,
        ps.UserPostRank,
        ps.TotalUserPosts,
        ps.AvgUserScore,
        ROW_NUMBER() OVER (ORDER BY ps.Score DESC) as GlobalScoreRank,
        RANK() OVER (PARTITION BY ps.PostTypeId ORDER BY ps.Score DESC) as TypeSpecificRank
    FROM PostStats ps
    WHERE ps.Score > 0
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsRequired,
        t.IsModeratorOnly,
        CASE 
            WHEN t.Count > 1000 THEN 'ExtremelyPopular'
            WHEN t.Count > 100 THEN 'VeryPopular'
            WHEN t.Count > 50 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as PostsWithTagCount,
        (SELECT AVG(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') as AvgScoreWithTag
    FROM Tags t
),
PostWithRelatedData AS (
    SELECT 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        COALESCE(u.DisplayName, 'Anonymous') as AuthorName,
        u.Reputation as AuthorReputation,
        u.Views as AuthorViews,
        u.UpVotes as AuthorUpvotes,
        u.DownVotes as AuthorDownvotes,
        ps.GlobalScoreRank,
        ps.TypeSpecificRank,
        ps.ViewCategory,
        ps.PostTypeCategory,
        ps.DaysSinceCreation,
        ta.PopularityLevel,
        ta.AvgScoreWithTag,
        CASE WHEN v.Id IS NOT NULL THEN 1 ELSE 0 END as HasVotes,
        COALESCE(b.UserId, 0) as BadgeCount,
        CASE 
            WHEN COUNT(ph.Id) > 0 THEN 'HasHistory'
            ELSE 'NoHistory'
        END as HistoryStatus,
        COUNT(DISTINCT c.Id) as CommentCountIncludingDeleted
    FROM Posts p
    INNER JOIN PostStats ps ON p.Id = ps.PostId
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN TagAnalysis ta ON p.Tags LIKE '%' || ta.TagName || '%'
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY 
        p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.ViewCount, p.AnswerCount,
        p.CommentCount, p.FavoriteCount, p.CreationDate, p.LastActivityDate,
        p.Title, p.Tags, p.AcceptedAnswerId, u.DisplayName, u.Reputation,
        u.Views, u.UpVotes, u.DownVotes, ps.GlobalScoreRank, ps.TypeSpecificRank,
        ps.ViewCategory, ps.PostTypeCategory, ps.DaysSinceCreation, 
        ta.PopularityLevel, ta.AvgScoreWithTag, b.UserId, ph.Id, c.Id
)
SELECT 
    'Query Result Set' as ResultType,
    COUNT(*) as TotalPosts,
    AVG(Score) as AvgScore,
    AVG(ViewCount) as AvgViews,
    AVG(AnswerCount) as AvgAnswerCount,
    AVG(CommentCount) as AvgCommentCount,
    AVG(FavoriteCount) as AvgFavoriteCount,
    COUNT(DISTINCT OwnerUserId) as DistinctAuthors,
    COUNT(CASE WHEN GlobalScoreRank <= 10 THEN 1 END) as Top10ScorePosts,
    COUNT(CASE WHEN TypeSpecificRank <= 5 THEN 1 END) as Top5TypePosts,
    COUNT(CASE WHEN ViewCategory = 'HighlyViewed' THEN 1 END) as HighlyViewedPosts,
    COUNT(CASE WHEN PostTypeCategory = 'QuestionWithAnswers' THEN 1 END) as QuestionsWithAnswers,
    COUNT(CASE WHEN HistoryStatus = 'HasHistory' THEN 1 END) as PostsWithHistory,
    AVG(AvgScoreWithTag) as AvgScoreWithTags,
    COUNT(CASE WHEN AuthorReputation > 10000 THEN 1 END) as HighReputationAuthors
FROM PostWithRelatedData
WHERE PostTypeId IN (1, 2) AND Score > 10
HAVING COUNT(*) > 0
UNION ALL
SELECT 
    'Aggregated Performance Metrics' as ResultType,
    AVG(Reputation) as TotalPosts,
    AVG(Views) as AvgScore,
    AVG(UpVotes) as AvgViews,
    AVG(DownVotes) as AvgAnswerCount,
    AVG(DaysSinceCreation) as AvgCommentCount,
    0 as AvgFavoriteCount,
    COUNT(*) as DistinctAuthors,
    COUNT(*) as Top10ScorePosts,
    COUNT(*) as Top5TypePosts,
    COUNT(*) as HighlyViewedPosts,
    COUNT(*) as QuestionsWithAnswers,
    COUNT(*) as PostsWithHistory,
    AVG(AvgScoreWithTag) as AvgScoreWithTags,
    COUNT(*) as HighReputationAuthors
FROM UserActivity ua
WHERE ua.TotalPosts > 0
UNION ALL
SELECT 
    'Tag-Based Statistics' as ResultType,
    AVG(TagCount) as TotalPosts,
    AVG(PostsWithTagCount) as AvgScore,
    AVG(AvgScoreWithTag) as AvgViews,
    COUNT(*) as DistinctAuthors,
    0 as Top10ScorePosts,
    0 as Top5TypePosts,
    0 as HighlyViewedPosts,
    0 as QuestionsWithAnswers,
    0 as PostsWithHistory,
    0 as AvgScoreWithTags,
    0 as HighReputationAuthors
FROM TagAnalysis ta
WHERE ta.TagCount > 0;