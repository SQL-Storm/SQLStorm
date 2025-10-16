-- {"query": "11063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 834} 
WITH RecentPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.CreationDate, 
        p.Score, 
        p.ViewCount, 
        u.DisplayName AS OwnerDisplayName, 
        u.Reputation AS OwnerReputation,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(CASE WHEN v.PostId IS NOT NULL THEN v.CreationDate ELSE NULL END) AS LatestVoteDate
    FROM 
        Posts p
    LEFT JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.CreationDate > (cast('2024-10-01' as date) - INTERVAL '14 days')
    WHERE 
        p.CreationDate > (cast('2024-10-01' as date) - INTERVAL '14 days')
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
UserActivity AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.LastAccessDate, 
        COUNT(DISTINCT p.Id) AS ActivePostsCount,
        COUNT(DISTINCT c.Id) AS ActiveCommentsCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        SUM(p.AnswerCount) AS TotalAnswerCount,
        SUM(p.CommentCount) AS TotalCommentCount,
        SUM(p.FavoriteCount) AS TotalFavoriteCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    WHERE 
        u.LastAccessDate > (cast('2024-10-01' as date) - INTERVAL '30 days')
    GROUP BY 
        u.Id, u.DisplayName, u.LastAccessDate
),
BadgeSummary AS (
    SELECT 
        b.UserId, 
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges b
    GROUP BY 
        b.UserId
)
SELECT 
    rp.Id AS PostId,
    rp.Title AS PostTitle,
    rp.CreationDate AS PostCreationDate,
    rp.Score AS PostScore,
    rp.ViewCount AS PostViewCount,
    rp.OwnerDisplayName,
    rp.OwnerReputation,
    rp.VoteCount,
    rp.UpVoteCount,
    rp.DownVoteCount,
    rp.LatestVoteDate,
    ua.ActivePostsCount,
    ua.ActiveCommentsCount,
    ua.TotalScore,
    ua.TotalViewCount,
    ua.TotalAnswerCount,
    ua.TotalCommentCount,
    ua.TotalFavoriteCount,
    bs.TotalBadges,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.Id = ua.Id
LEFT JOIN 
    BadgeSummary bs ON rp.Id = bs.UserId
ORDER BY 
    rp.CreationDate DESC, rp.Score DESC, ua.TotalScore DESC, bs.TotalBadges DESC
LIMIT 100;