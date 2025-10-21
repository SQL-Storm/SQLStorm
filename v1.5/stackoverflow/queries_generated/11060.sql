-- {"query": "11060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "nova-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2098, "output_tokens": 722} 

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
        COUNT(DISTINCT v.UserId) AS UniqueVoters,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(c.Id) AS CommentCount
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    WHERE 
        p.CreationDate > CURRENT_DATE - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
UserActivity AS (
    SELECT 
        UserId, 
        COUNT(Id) AS TotalPosts, 
        SUM(Score) AS TotalScore, 
        SUM(ViewCount) AS TotalViews, 
        SUM(CommentCount) AS TotalComments
    FROM 
        Posts
    GROUP BY 
        UserId
),
BadgeRank AS (
    SELECT 
        UserId, 
        MAX(Date) AS LatestBadgeDate, 
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM 
        Badges
    GROUP BY 
        UserId
)
SELECT 
    rp.Id AS PostId, 
    rp.Title, 
    rp.CreationDate, 
    rp.Score, 
    rp.ViewCount, 
    rp.OwnerDisplayName, 
    rp.OwnerReputation, 
    rp.VoteCount, 
    rp.UniqueVoters, 
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.LastCommentDate, 
    rp.CommentCount, 
    ua.TotalPosts, 
    ua.TotalScore, 
    ua.TotalViews, 
    ua.TotalComments, 
    br.LatestBadgeDate, 
    br.GoldBadges, 
    br.SilverBadges, 
    br.BronzeBadges
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN 
    BadgeRank br ON rp.OwnerUserId = br.UserId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.LastCommentDate DESC, 
    br.GoldBadges DESC, 
    br.SilverBadges DESC, 
    br.BronzeBadges DESC
LIMIT 100;
