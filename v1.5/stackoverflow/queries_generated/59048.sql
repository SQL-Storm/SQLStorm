-- {"query": "59048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 832} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) as CommentCount,
    COUNT(DISTINCT v.Id) as VoteCount,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') as Tags,
    MAX(ph.CreationDate) as LastActivityDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END as PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END as PostStatus,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) as Upvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) as Downvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) as Favorites,
    COUNT(DISTINCT bl.Id) as BountyCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END), 0) as TotalBounty,
    STRING_AGG(DISTINCT b.Name, ', ') as BadgeNames,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    AVG(p.Score) OVER (PARTITION BY u.Id) as AvgScorePerUser,
    RANK() OVER (ORDER BY p.Score DESC) as ScoreRank,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) as ViewRank,
    COUNT(*) OVER () as TotalPosts,
    p.Body
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Tags t ON p.Tags IS NOT NULL AND t.TagName IN (
    SELECT UNNEST(STRING_TO_ARRAY(REPLACE(REPLACE(p.Tags, '<', ''), '>', ''), '><'))
)
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT PostId, COUNT(*) as BountyCount, SUM(BountyAmount) as TotalBounty
    FROM Votes 
    WHERE VoteTypeId = 8 
    GROUP BY PostId
) bl ON p.Id = bl.PostId
WHERE p.CreationDate >= '2020-01-01' 
    AND p.PostTypeId IN (1, 2)
    AND (p.ViewCount > 100 OR p.Score > 50)
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId, p.Body
HAVING COUNT(DISTINCT c.Id) > 0
    AND COUNT(DISTINCT v.Id) > 1
    AND COUNT(DISTINCT ph.Id) > 2
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;