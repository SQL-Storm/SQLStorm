-- {"query": "59052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 662} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) as TotalQuestionScore,
    SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) as TotalAnswerScore,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) as AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) as AvgAnswerScore,
    MAX(p.CreationDate) as LatestPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    COUNT(DISTINCT c.Id) as TotalComments,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    COUNT(DISTINCT v.Id) as TotalVotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.PostId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN Posts p2 ON p.ParentId = p2.Id
LEFT JOIN (
    SELECT PostId, STRING_AGG(TagName, ' ') as TagName
    FROM Posts p
    JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    GROUP BY PostId
) t ON p.Id = t.PostId
WHERE u.CreationDate >= '2010-01-01 00:00:00'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 10
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000;