WITH TopUsers AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM 
        Users u
    WHERE 
        u.Reputation > 1000
), ActivePosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        p.CreationDate
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    WHERE 
        p.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY)
    GROUP BY 
        p.Id,
        p.Title,
        p.PostTypeId,
        p.CreationDate
), PostRankings AS (
    SELECT 
        ap.PostId,
        ap.Title,
        ap.CommentCount,
        ap.UpVotes,
        ap.DownVotes,
        RANK() OVER (ORDER BY (ap.UpVotes - ap.DownVotes) DESC, ap.CommentCount DESC) AS PostRank
    FROM 
        ActivePosts ap
)
SELECT 
    tu.DisplayName,
    tu.Reputation,
    pr.Title,
    pr.CommentCount,
    pr.UpVotes,
    pr.DownVotes,
    pr.PostRank,
    CASE 
        WHEN pr.PostRank <= 5 THEN 'Top Post'
        WHEN pr.PostRank <= 10 THEN 'High Engagement'
        ELSE 'Moderate Engagement'
    END AS EngagementLevel
FROM 
    TopUsers tu
JOIN 
    PostRankings pr ON tu.Id = (
        SELECT p2.OwnerUserId
        FROM Posts p2
        WHERE p2.Id = pr.PostId
        LIMIT 1
    )
WHERE 
    pr.CommentCount > 0
ORDER BY 
    pr.PostRank, tu.Reputation DESC
LIMIT 10;