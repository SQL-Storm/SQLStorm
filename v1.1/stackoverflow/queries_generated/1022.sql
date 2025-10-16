-- {"query": "1022.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 463} 

WITH RankedPosts AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.OwnerUserId, 
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn,
        SUM(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS total_views
    FROM 
        Posts p
    WHERE 
        p.CreationDate >= NOW() - INTERVAL '1 year' 
        AND p.PostTypeId = 1
),
UserDetails AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation, 
        u.Views, 
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.Views
),
TopUsers AS (
    SELECT 
        ud.UserId, 
        ud.DisplayName, 
        ud.Reputation, 
        ud.Views, 
        ud.BadgeCount,
        SUM(rp.Score) AS TotalScore
    FROM 
        UserDetails ud
    JOIN 
        RankedPosts rp ON ud.UserId = rp.OwnerUserId
    GROUP BY 
        ud.UserId, ud.DisplayName, ud.Reputation, ud.Views, ud.BadgeCount
    HAVING 
        COUNT(rp.Id) > 5
    ORDER BY 
        TotalScore DESC
    LIMIT 10
)
SELECT 
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.Views,
    tu.BadgeCount,
    tp.Title AS TopPostTitle,
    tp.Score AS TopPostScore,
    tp.ViewCount AS TopPostViewCount,
    tp.CreationDate AS TopPostDate
FROM 
    TopUsers tu
LEFT JOIN 
    RankedPosts tp ON tu.UserId = tp.OwnerUserId AND tp.rn = 1
WHERE 
    tu.Views IS NOT NULL
ORDER BY 
    tu.Reputation DESC,
    tu.BadgeCount DESC;
