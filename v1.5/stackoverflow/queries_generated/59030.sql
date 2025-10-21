-- {"query": "59030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 600} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) as QuestionsWithAcceptedAnswers,
    COUNT(DISTINCT b.Id) as Badges,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as Comments,
    COUNT(DISTINCT v.Id) as Votes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) as Upvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) as Downvotes,
    COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) as Favorites,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    COUNT(DISTINCT pl.Id) as PostLinks,
    COUNT(DISTINCT t.Id) as TagsUsed,
    AVG(p.Score) as AvgPostScore,
    MAX(p.CreationDate) as LastPostDate,
    MIN(p.CreationDate) as FirstPostDate,
    DATEDIFF(MAX(p.CreationDate), MIN(p.CreationDate)) as DaysActive,
    COUNT(DISTINCT p.OwnerUserId) as DistinctPostOwners,
    COUNT(DISTINCT p.LastEditorUserId) as DistinctEditors,
    COUNT(DISTINCT CASE WHEN p.ViewCount > 0 THEN p.Id END) as ViewedPosts
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId OR u.Id = p.LastEditorUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId OR u.Id = c.LastEditorUserId
LEFT JOIN Votes v ON u.Id = v.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN PostLinks pl ON u.Id = pl.Id
LEFT JOIN Tags t ON u.Id IN (
    SELECT DISTINCT p.OwnerUserId 
    FROM Posts p 
    WHERE p.Tags LIKE '%' || t.TagName || '%'
) 
WHERE u.Id BETWEEN 1 AND 10000
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000;