-- Performance Benchmarking SQL Query

-- This query will fetch statistics on posts, users, and votes 
-- to assess the performance and interaction within the Stack Overflow community.

WITH PostStats AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(v.BountyAmount) AS TotalBounties
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId = 8  -- BountyStart
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.ViewCount, p.Score
),
UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostsCount,
        SUM(b.Class = 1) AS GoldBadges,    -- Gold Badge Count
        SUM(b.Class = 2) AS SilverBadges,  -- Silver Badge Count
        SUM(b.Class = 3) AS BronzeBadges   -- Bronze Badge Count
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
VoteStats AS (
    SELECT 
        v.UserId,
        COUNT(DISTINCT v.PostId) AS VotesCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,  -- Upvote Count
        SUM(v.VoteTypeId = 3) AS DownVotes  -- Downvote Count
    FROM 
        Votes v
    GROUP BY 
        v.UserId
)

SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.PostsCount,
    ps.PostId,
    ps.Title,
    ps.CreationDate,
    ps.ViewCount,
    ps.Score,
    ps.CommentCount,
    ps.AnswerCount,
    ps.TotalBounties,
    vs.VotesCount,
    vs.UpVotes,
    vs.DownVotes,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges
FROM 
    UserStats us
JOIN 
    PostStats ps ON us.UserId = ps.OwnerUserId
LEFT JOIN 
    VoteStats vs ON us.UserId = vs.UserId
ORDER BY 
    us.Reputation DESC,
    ps.Score DESC;
