-- {"query": "59047.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1207} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) AS Wikis,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id END) AS TagWikiExcerpts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id END) AS TagWikis,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 6 THEN p.Id END) AS ModeratorNominations,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 7 THEN p.Id END) AS WikiPlaceholders,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 8 THEN p.Id END) AS PrivilegeWikis,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.ViewCount ELSE NULL END) AS AvgAnswerViews,
    COUNT(DISTINCT b.Id) AS BadgesReceived,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteVotes,
    COUNT(DISTINCT c.Id) AS CommentsMade,
    COUNT(DISTINCT ph.Id) AS PostHistoryEntries,
    COUNT(DISTINCT pl.Id) AS PostLinks,
    MAX(p.CreationDate) AS LastPostDate,
    MAX(u.LastAccessDate) AS LastAccessDate,
    STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.ParentId IS NOT NULL THEN p.Id END) AS AnswersToQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL THEN p.Id END) AS ClosedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommunityOwnedDate IS NOT NULL THEN p.Id END) AS CommunityOwnedQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 THEN p.Id END) AS QuestionsWithAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 0 THEN p.Id END) AS QuestionsWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.FavoriteCount > 0 THEN p.Id END) AS QuestionsWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.CommentCount > 0 THEN p.Id END) AS AnswerWithComments,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.FavoriteCount > 0 THEN p.Id END) AS AnswerWithFavorites,
    COUNT(DISTINCT CASE WHEN p.PostTypeId IN (1, 2) AND p.Score > 0 THEN p.Id END) AS HighScorePosts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN ph.Id END) AS PostStatusChanges,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 7) THEN ph.Id END) AS TitleEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (2, 5, 8) THEN ph.Id END) AS BodyEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (3, 6, 9) THEN ph.Id END) AS TagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24, 35, 36) THEN ph.Id END) AS SuggestedEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (19, 20) THEN ph.Id END) AS QuestionProtectionChanges,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (16, 17) THEN ph.Id END) AS CommunityOwnershipChanges
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN (
    SELECT Id, UNNEST(string_to_array(Tags, '><')) AS TagName
    FROM Posts
    WHERE PostTypeId = 1 AND Tags IS NOT NULL AND Tags != ''
) t ON p.Id = t.Id
WHERE u.Id IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 10000;