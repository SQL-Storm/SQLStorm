-- {"query": "43069.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 557} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId, 
        COUNT(DISTINCT p.Id) AS PostsCount, 
        COUNT(DISTINCT c.Id) AS CommentsCount, 
        SUM(p.Score) AS TotalScore,
        COUNT(DISTINCT b.Id) AS BadgesCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Comments c ON u.Id = c.UserId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
    GROUP BY 
        u.Id
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
PostDetails AS (
    SELECT 
        p.Id AS PostId, 
        p.CreationDate, 
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        ph.CreationDate AS LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS rn
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 5
    WHERE 
        p.PostTypeId = 1
),
TopUserPosts AS (
    SELECT 
        OwnerUserId,
        AVG(Score) AS AvgScore,
        MAX(ViewCount) AS MaxViewCount,
        COUNT(*) AS TotalQuestions
    FROM 
        PostDetails
    WHERE 
        rn <= 10
    GROUP BY 
        OwnerUserId
)
SELECT 
    ua.UserId,
    ua.PostsCount,
    ua.CommentsCount,
    ua.TotalScore,
    ua.BadgesCount,
    COALESCE(tup.AvgScore, 0) AS AvgTopQuestionScore,
    COALESCE(tup.MaxViewCount, 0) AS MaxTopQuestionViewCount,
    COALESCE(tup.TotalQuestions, 0) AS TotalTopQuestions
FROM 
    UserActivity ua
LEFT JOIN 
    TopUserPosts tup ON ua.UserId = tup.OwnerUserId
ORDER BY 
    ua.TotalScore DESC, 
    tup.AvgScore DESC
LIMIT 50;