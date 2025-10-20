-- {"query": "59025.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1665} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS Wikis,
    COUNT(DISTINCT b.Id) AS Badges,
    COUNT(DISTINCT c.Id) AS Comments,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    COUNT(DISTINCT v.Id) AS Votes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END) AS AvgAnswerViews,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS EarliestPostDate,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CreationDate >= '2023-01-01' THEN p.Id END) AS Questions2023,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CreationDate >= '2023-01-01' THEN p.Id END) AS Answers2023,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 100 THEN p.Id END) AS HighScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 100 THEN p.Id END) AS HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN p.Id END) AS TaggedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswerWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) AS FavoritedQuestions,
    CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 100 THEN p.Id END) > 0 THEN 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score >= 100 THEN p.Id END) * 100.0 / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) 
    ELSE 0 END AS HighScoreQuestionPercentage,
    CASE WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 100 THEN p.Id END) > 0 THEN 
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score >= 100 THEN p.Id END) * 100.0 / COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) 
    ELSE 0 END AS HighScoreAnswerPercentage,
    COUNT(DISTINCT CASE WHEN b.Name = 'Good Answer' THEN b.Id END) AS GoodAnswerBadges,
    COUNT(DISTINCT CASE WHEN b.Name = 'Good Question' THEN b.Id END) AS GoodQuestionBadges,
    COUNT(DISTINCT CASE WHEN b.Name = 'Great Answer' THEN b.Id END) AS GreatAnswerBadges,
    COUNT(DISTINCT CASE WHEN b.Name = 'Great Question' THEN b.Id END) AS GreatQuestionBadges,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS Favorites,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 6 THEN v.Id END) AS CloseVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 7 THEN v.Id END) AS ReopenVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 8 THEN v.Id END) AS BountyStarts,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 9 THEN v.Id END) AS BountyCloses,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 10 THEN v.Id END) AS Deletions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 11 THEN v.Id END) AS Undeletions,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 12 THEN v.Id END) AS SpamFlags,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 14 THEN v.Id END) AS ModeratorNominations,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 15 THEN v.Id END) AS ModeratorReviews,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 16 THEN v.Id END) AS EditSuggestions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN ph.Id END) AS Edits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) AS StatusChanges,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (14, 15) THEN ph.Id END) AS LockUnlockEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (19, 20) THEN ph.Id END) AS ProtectionEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (33, 34) THEN ph.Id END) AS NoticeEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.Id END) AS MigrationEvents,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 1 THEN pl.Id END) AS LinkedPosts,
    COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.Id END) AS DuplicatePosts,
    COUNT(DISTINCT CASE WHEN c.UserId IS NOT NULL THEN c.Id END) AS CommentsByUser,
    COUNT(DISTINCT CASE WHEN c.UserId IS NULL THEN c.Id END) AS AnonymousComments
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId OR u.Id = pl.RelatedPostId
LEFT JOIN Votes v ON u.Id = v.UserId
WHERE u.CreationDate >= '2020-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 100
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 100;