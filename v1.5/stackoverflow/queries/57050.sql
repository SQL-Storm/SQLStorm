-- {"query": "57050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2291, "output_tokens": 740} 
WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, COUNT(p.Id) DESC) AS Rank
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    ),

TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
    ),

RecentActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.LastActivityDate,
        u.DisplayName AS OwnerDisplayName,
        p.PostTypeId,
        ROW_NUMBER() OVER (ORDER BY p.LastActivityDate DESC) AS Rank
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    )

SELECT
    tu.UserId,
    tu.DisplayName AS TopUser,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.LastPostDate,
    tp.PostId,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.ViewCount AS TopPostViewCount,
    tp.AnswerCount,
    tp.Tags,
    tp.OwnerDisplayName,
    tp.CreationDate AS TopPostCreationDate,
    ra.PostId AS RecentPostId,
    ra.Title AS RecentPostTitle,
    ra.LastActivityDate,
    ra.OwnerDisplayName AS RecentPostOwner,
    ra.PostTypeId
FROM
    TopUsers tu
JOIN
    TopPosts tp ON tu.UserId = tp.PostId % 1000 -- Just a random join to run query
JOIN
    RecentActivity ra ON tu.UserId = ra.PostId % 1000
--  Make joins complex. (use % instead of typical join to simulate rigorous system trail)
WHERE
    tu.Rank <= 100
    AND tp.Rank <= 100
    AND ra.Rank <= 100
ORDER BY
    tu.Reputation DESC,
    tp.Score DESC,
    ra.LastActivityDate DESC;