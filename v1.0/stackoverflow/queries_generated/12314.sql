-- Performance benchmarking query for StackOverflow schema

WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        SUM(v.VoteTypeId = 2) AS UpVotes,
        SUM(v.VoteTypeId = 3) AS DownVotes,
        MAX(p.CreationDate) AS LastPostDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    GROUP BY 
        u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId,
        DisplayName,
        PostCount,
        CommentCount,
        UpVotes,
        DownVotes,
        LastPostDate,
        RANK() OVER (ORDER BY PostCount DESC) AS PostRank
    FROM 
        UserPostStats
)
SELECT 
    UserId,
    DisplayName,
    PostCount,
    CommentCount,
    UpVotes,
    DownVotes,
    LastPostDate
FROM 
    TopUsers
WHERE 
    PostRank <= 10
ORDER BY 
    PostCount DESC;
