-- {"query": "59022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 2001} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT b.Id) AS Badges,
    COUNT(DISTINCT c.Id) AS Comments,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    COUNT(DISTINCT v.Id) AS Votes,
    AVG(p.Score) AS AverageScore,
    MAX(p.CreationDate) AS LatestPostDate,
    MIN(p.CreationDate) AS EarliestPostDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswersWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) AS QuestionsWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.FavoriteCount > 0 THEN p.Id END) AS AnswersWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) AS HighlyViewedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ViewCount > 1000 THEN p.Id END) AS HighlyViewedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 100 THEN p.Id END) AS HighScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 100 THEN p.Id END) AS HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score < 0 THEN p.Id END) AS NegativeScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score < 0 THEN p.Id END) AS NegativeScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.LastActivityDate > u.LastAccessDate THEN p.Id END) AS ActiveQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.LastActivityDate > u.LastAccessDate THEN p.Id END) AS ActiveAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.LastEditDate > p.CreationDate THEN p.Id END) AS EditedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.LastEditDate > p.CreationDate THEN p.Id END) AS EditedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Title IS NOT NULL THEN p.Id END) AS QuestionsWithTitles,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Title IS NOT NULL THEN p.Id END) AS AnswersWithTitles,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN p.Id END) AS QuestionsWithTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Tags IS NOT NULL THEN p.Id END) AS AnswersWithTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Body IS NOT NULL THEN p.Id END) AS QuestionsWithBodies,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Body IS NOT NULL THEN p.Id END) AS AnswersWithBodies,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id THEN p.Id END) AS OwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id THEN p.Id END) AS OwnedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId != u.Id THEN p.Id END) AS NonOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId != u.Id THEN p.Id END) AS NonOwnedAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.AnswerCount = 0 THEN p.Id END) AS OwnedQuestionsWithoutAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.ParentId IS NOT NULL THEN p.Id END) AS OwnedAnswersWithParent,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.ParentId IS NOT NULL THEN p.Id END) AS OwnedQuestionsWithParent,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 THEN p.Id END) AS OwnedQuestionPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 THEN p.Id END) AS OwnedAnswerPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS OwnedQuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) AS OwnedAnswersWithParents,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.AnswerCount = 0 THEN p.Id END) AS OwnedQuestionsWithoutAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN p.Id END) AS OwnedQuestionsWithTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Tags IS NOT NULL THEN p.Id END) AS OwnedAnswersWithTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Body IS NOT NULL THEN p.Id END) AS OwnedQuestionsWithBodies,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Body IS NOT NULL THEN p.Id END) AS OwnedAnswersWithBodies,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.Title IS NOT NULL THEN p.Id END) AS OwnedQuestionsWithTitles,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.Title IS NOT NULL THEN p.Id END) AS OwnedAnswersWithTitles,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.OwnerUserId = u.Id AND p.PostTypeId = 1 AND p.CreationDate >= '2022-01-01' THEN p.Id END) AS OwnedQuestions2022,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.OwnerUserId = u.Id AND p.PostTypeId = 2 AND p.CreationDate >= '2022-01-01' THEN p.Id END) AS OwnedAnswers2022
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN (
    SELECT DISTINCT PostId, TagName
    FROM Posts p
    JOIN LATERAL (
        SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS TagName
    ) t ON TRUE
) AS tag_posts ON p.Id = tag_posts.PostId
LEFT JOIN Tags t ON tag_posts.TagName = t.TagName
WHERE u.Id IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation
ORDER BY u.Reputation DESC
LIMIT 1000;