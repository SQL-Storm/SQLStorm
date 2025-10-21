-- {"query": "43090.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 578} 

WITH UserReputation AS (
    SELECT 
        u.Id, 
        u.DisplayName, 
        u.Reputation, 
        SUM(b.Class) AS BadgeScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.LastAccessDate > CURRENT_DATE - INTERVAL '3 months'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopQuestions AS (
    SELECT 
        p.Id, 
        p.Title, 
        p.ViewCount, 
        p.Score,
        COUNT(DISTINCT ph.UserId) AS EditorCount
    FROM 
        Posts p
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        p.PostTypeId = 1 
        AND p.CreationDate > CURRENT_DATE - INTERVAL '1 year'
        AND p.ClosedDate IS NULL
    GROUP BY 
        p.Id
    HAVING 
        COUNT(ph.Id) > 5
    ORDER BY 
        p.Score DESC
    LIMIT 100
),
UserQuestionActivity AS (
    SELECT 
        ph.UserId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.PostId END) AS InitialPosts,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.PostId END) AS EditedPosts
    FROM 
        PostHistory ph
    WHERE 
        ph.CreationDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY 
        ph.UserId
)
SELECT 
    ur.DisplayName,
    ur.Reputation,
    ur.BadgeScore,
    tq.Title,
    tq.ViewCount,
    tq.Score,
    ua.InitialPosts,
    ua.EditedPosts
FROM 
    UserReputation ur
JOIN 
    TopQuestions tq ON ur.Id = tq.OwnerUserId
JOIN 
    UserQuestionActivity ua ON ur.Id = ua.UserId
WHERE 
    ur.ReputationRank <= 10
ORDER BY 
    ur.Reputation DESC, tq.Score DESC;
