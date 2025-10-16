WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS HighestBounty,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkCount
    FROM 
        Posts p
    INNER JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostLinks pl ON p.Id = pl.PostId
    WHERE 
        p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, u.DisplayName, u.Reputation
),
BadgeSummary AS (
    SELECT 
        b.UserId,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.VoteCount,
    rp.UpVoteCount,
    rp.DownVoteCount,
    rp.HighestBounty,
    rp.CommentCount,
    rp.LinkCount,
    COALESCE(bs.GoldBadgeCount, 0) AS GoldBadgeCount,
    COALESCE(bs.SilverBadgeCount, 0) AS SilverBadgeCount,
    COALESCE(bs.BronzeBadgeCount, 0) AS BronzeBadgeCount,
    (rp.Score + rp.ViewCount * 1.5 + rp.UpVoteCount * 2 - rp.DownVoteCount) AS PerformanceScore
FROM 
    RecentPosts rp
LEFT JOIN 
    BadgeSummary bs ON rp.OwnerUserId = bs.UserId
ORDER BY 
    PerformanceScore DESC
LIMIT 10;