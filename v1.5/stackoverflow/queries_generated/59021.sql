-- {"query": "59021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1137} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT v.Id) as Votes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
    COUNT(DISTINCT pl.Id) as PostLinks,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
    MAX(p.CreationDate) as LatestPostDate,
    MAX(p.Score) as HighestScore,
    AVG(p.Score) as AverageScore,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.ViewCount > 1000 THEN p.Id END) as HighViewQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Score > 100 THEN p.Id END) as HighScoreQuestions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 50 THEN p.Id END) as HighScoreAnswers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.CommentCount > 10 THEN p.Id END) as QuestionsWithManyComments,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.Id END) as CloseReopenEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (12, 13) THEN ph.Id END) as DeleteUndeleteEvents,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.Id END) as CommunityOwnedEvents,
    COUNT(DISTINCT CASE WHEN u.Location IS NOT NULL AND u.Location != '' THEN u.Id END) as UsersWithLocation,
    COUNT(DISTINCT CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl != '' THEN u.Id END) as UsersWithWebsite,
    COUNT(DISTINCT CASE WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 50 THEN u.Id END) as UsersWithLongAboutMe,
    COUNT(DISTINCT CASE WHEN u.UpVotes > 1000 THEN u.Id END) as UsersWithManyUpVotes,
    COUNT(DISTINCT CASE WHEN u.DownVotes > 1000 THEN u.Id END) as UsersWithManyDownVotes,
    COUNT(DISTINCT CASE WHEN u.Views > 10000 THEN u.Id END) as UsersWithHighViews,
    COUNT(DISTINCT CASE WHEN u.Reputation > 100000 THEN u.Id END) as UsersWithHighReputation,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as TotalQuestionViews,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) as AverageQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AverageQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AverageAnswerScore,
    MAX(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) as MaxQuestionViews,
    MAX(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as MaxAnswerScore
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId OR u.Id = pl.RelatedPostId
LEFT JOIN (
    SELECT DISTINCT UserId, TagName 
    FROM Posts p
    CROSS JOIN unnest(string_to_array(p.Tags, '><')) AS TagName
    WHERE p.Tags IS NOT NULL AND p.Tags != ''
) t ON u.Id = t.UserId
WHERE u.Id IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 10000;