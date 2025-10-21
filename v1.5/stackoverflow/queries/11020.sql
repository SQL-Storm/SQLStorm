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
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY MAX(v.CreationDate) DESC) AS LatestVoteOrder
    FROM 
        Posts p
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > DATE '2024-10-01' - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, u.DisplayName, u.Reputation
),
UserActivity AS (
    SELECT 
        CAST(p.OwnerUserId AS varchar) AS UserId, 
        COUNT(p.Id) AS TotalPosts, 
        SUM(p.Score) AS TotalScore, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes, 
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM 
        Posts p
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        p.OwnerUserId
),
TopUsers AS (
    SELECT 
        ua.UserId, 
        ua.TotalPosts, 
        ua.TotalScore, 
        ua.TotalUpVotes, 
        ua.TotalDownVotes
    FROM 
        UserActivity ua
    WHERE 
        ua.TotalPosts > 10
    ORDER BY 
        ua.TotalScore DESC
    LIMIT 10
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
    rp.UpVoteCount, 
    rp.DownVoteCount, 
    rp.AcceptedVoteCount, 
    COALESCE(ua.TotalPosts, 0) AS UserTotalPosts, 
    COALESCE(ua.TotalScore, 0) AS UserTotalScore, 
    COALESCE(ua.TotalUpVotes, 0) AS UserTotalUpVotes, 
    COALESCE(ua.TotalDownVotes, 0) AS UserTotalDownVotes
FROM 
    RecentPosts rp
LEFT JOIN 
    UserActivity ua ON rp.OwnerDisplayName = ua.UserId
LEFT JOIN 
    TopUsers tu ON rp.OwnerDisplayName = tu.UserId
ORDER BY 
    rp.Score DESC, 
    rp.ViewCount DESC, 
    rp.CreationDate DESC;