WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY p.CreationDate DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)  -- Considering only upvotes and downvotes
    WHERE 
        p.PostTypeId = 1  -- Only considering Questions
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.Score
),
FilteredPosts AS (
    SELECT 
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.CommentCount,
        rp.VoteCount
    FROM 
        RankedPosts rp
    WHERE 
        rp.rn = 1  -- Only the most recent version of each post
      AND 
        rp.CommentCount > 5  -- Only include posts with more than 5 comments
      AND 
        rp.VoteCount >= 10  -- Only include posts with at least 10 votes
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostsCreated,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 3  -- Users who have created more than 3 posts
)
SELECT 
    fp.Title AS PostTitle,
    fp.CreationDate AS PostCreationDate,
    fp.Score AS PostScore,
    tu.DisplayName AS UserName,
    tu.PostsCreated,
    tu.BadgesEarned,
    LPAD(tu.BadgesEarned::TEXT, 2, '0') AS FormattedBadgesEarned
FROM 
    FilteredPosts fp
JOIN 
    Users u ON fp.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id)
JOIN 
    TopUsers tu ON tu.UserId = u.Id
ORDER BY 
    fp.Score DESC, tu.BadgesEarned DESC
LIMIT 10;
