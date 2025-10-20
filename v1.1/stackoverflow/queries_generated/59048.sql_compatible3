SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT ph.Id) AS HistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    MAX(ph.CreationDate) AS LastActivityDate,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        ELSE 'Other'
    END AS PostType,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answer Accepted'
        ELSE 'Open'
    END AS PostStatus,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS Upvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS Downvotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END), 0) AS Favorites,
    COALESCE(bl.BountyCount, 0) AS BountyCount,
    COALESCE(bl.TotalBounty, 0) AS TotalBounty,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgScorePerUser,
    RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC) AS ViewRank,
    COUNT(*) OVER () AS TotalPosts,
    p.Body
FROM Posts p
INNER JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT p_inner.Id AS post_id, TRIM(tag_item) AS TagName
    FROM Posts p_inner,
         (
            SELECT unnest_el AS tag_item
            FROM (
                SELECT unnest(string_to_array(regexp_replace(p_inner.Tags, '[<>]', '', 'g'), '><')) AS unnest_el
            ) sub
         ) derived
) t ON p.Id = t.post_id
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS BountyCount, SUM(BountyAmount) AS TotalBounty
    FROM Votes 
    WHERE VoteTypeId = 8 
    GROUP BY PostId
) bl ON p.Id = bl.PostId
WHERE p.CreationDate >= DATE '2020-01-01'
    AND p.PostTypeId IN (1, 2)
    AND (p.ViewCount > 100 OR p.Score > 50)
GROUP BY 
    p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation, 
    p.PostTypeId, p.ClosedDate, p.CommunityOwnedDate, p.AcceptedAnswerId, p.Body,
    bl.BountyCount, bl.TotalBounty, u.Id
HAVING COUNT(DISTINCT c.Id) > 0
    AND COUNT(DISTINCT v.Id) > 1
    AND COUNT(DISTINCT ph.Id) > 2
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;