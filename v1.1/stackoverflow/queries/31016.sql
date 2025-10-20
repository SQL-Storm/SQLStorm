-- {"query": "31016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 441} 
WITH RankedPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS Rank
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1 -- Questions only
        AND p.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
),
TopUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        SUM(COALESCE(p.Score, 0)) AS TotalScore
    FROM 
        Users u
    JOIN 
        Posts p ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1 -- Questions only
    GROUP BY 
        u.Id, u.DisplayName
    HAVING 
        COUNT(DISTINCT p.Id) > 10
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(b.Id) AS BadgeCount
    FROM 
        Badges b
    GROUP BY 
        b.UserId
),
FinalResults AS (
    SELECT 
        tu.DisplayName,
        tu.QuestionCount,
        tu.TotalScore,
        COALESCE(ub.BadgeCount, 0) AS BadgeCount,
        COUNT(rp.PostId) AS TopPosts
    FROM 
        TopUsers tu
    LEFT JOIN 
        UserBadges ub ON tu.UserId = ub.UserId
    LEFT JOIN 
        RankedPosts rp ON tu.UserId = rp.OwnerUserId AND rp.Rank <= 5
    GROUP BY 
        tu.DisplayName, tu.QuestionCount, tu.TotalScore, ub.BadgeCount
)
SELECT 
    DisplayName,
    QuestionCount,
    TotalScore,
    BadgeCount,
    TopPosts
FROM 
    FinalResults
ORDER BY 
    TotalScore DESC,
    BadgeCount DESC,
    TopPosts DESC
LIMIT 10;