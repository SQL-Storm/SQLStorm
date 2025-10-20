-- {"query": "2020.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 508} 

WITH UserReputationChanges AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        COALESCE(SUM(vt.BountyAmount), 0) AS TotalBounty,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS TotalUpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS TotalDownVotes
    FROM 
        Users u
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Votes vt ON (v.PostId = vt.PostId AND vt.VoteTypeId = 8)
    GROUP BY 
        u.Id, u.DisplayName
),
PostInteraction AS (
    SELECT 
        p.Id AS PostId, 
        COUNT(DISTINCT c.Id) AS CommentCount, 
        COUNT(DISTINCT v.Id) AS VoteCount, 
        COALESCE(MAX(ahn.VoteDate), p.CreationDate) AS LastInteractionDate
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN (
        SELECT 
            v.PostId, 
            MAX(v.CreationDate) AS VoteDate
        FROM 
            Votes v
        WHERE 
            v.VoteTypeId IN (2,3)
        GROUP BY 
            v.PostId
    ) ahn ON p.Id = ahn.PostId
    GROUP BY 
        p.Id, p.CreationDate
)
SELECT 
    ur.UserId, 
    ur.DisplayName, 
    ur.TotalBounty,
    ur.TotalUpVotes, 
    ur.TotalDownVotes,
    pi.CommentCount,
    pi.VoteCount,
    pi.LastInteractionDate,
    CASE 
        WHEN ur.TotalBounty > 100 THEN 'Bounty Hunter'
        WHEN ur.TotalUpVotes > ur.TotalDownVotes THEN 'Popular User'
        ELSE 'Neutral User'
    END AS UserStatus
FROM 
    UserReputationChanges ur
JOIN 
    Posts p ON ur.UserId = p.OwnerUserId
JOIN 
    PostInteraction pi ON p.Id = pi.PostId
WHERE 
    ur.TotalUpVotes + ur.TotalDownVotes > 5
ORDER BY 
    ur.TotalUpVotes DESC, pi.CommentCount DESC;
