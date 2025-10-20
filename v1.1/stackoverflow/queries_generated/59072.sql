-- {"query": "59072.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 749} 
SELECT 
    p.PostTypeId,
    COUNT(*) as PostCount,
    AVG(p.Score) as AvgScore,
    MAX(p.ViewCount) as MaxViews,
    MIN(p.CreationDate) as EarliestPost,
    MAX(p.LastActivityDate) as LatestActivity,
    STRING_AGG(DISTINCT u.DisplayName, ', ') as Authors,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    COUNT(DISTINCT CASE WHEN p.OwnerUserId IS NOT NULL THEN p.OwnerUserId END) as UniqueAuthors,
    COUNT(DISTINCT CASE WHEN p.ParentId IS NOT NULL THEN p.ParentId END) as ParentQuestions,
    COUNT(DISTINCT CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN p.AcceptedAnswerId END) as AcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.CommentCount > 0 THEN p.Id END) as QuestionWithComments,
    COUNT(DISTINCT CASE WHEN p.FavoriteCount > 0 THEN p.Id END) as FavoriteQuestions,
    COUNT(DISTINCT CASE WHEN p.ClosedDate IS NOT NULL THEN p.Id END) as ClosedPosts,
    COUNT(DISTINCT CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN p.Id END) as CommunityOwnedPosts,
    COUNT(DISTINCT CASE WHEN p.AnswerCount > 0 THEN p.Id END) as QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.AnswerCount = 0 THEN p.Id END) as QuestionWithoutAnswers,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.PostId END) as Favorites,
    COUNT(DISTINCT b.UserId) as BadgeHolders,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.UserId END) as GoldBadgeHolders,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.UserId END) as SilverBadgeHolders,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.UserId END) as BronzeBadgeHolders,
    COUNT(DISTINCT ph.PostId) as PostHistoryEntries,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.PostId END) as PostStatusChanges,
    COUNT(DISTINCT pl.PostId) as LinkedPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.PostId END) as DuplicatePosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.PostId END) as LinkedPostsExplicit
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
WHERE p.CreationDate >= '2023-01-01' 
    AND p.CreationDate <= '2023-12-31'
    AND p.PostTypeId IN (1, 2, 3)
GROUP BY p.PostTypeId
HAVING COUNT(*) > 1000
ORDER BY 
    PostCount DESC,
    AvgScore DESC,
    MaxViews DESC
LIMIT 1000000;