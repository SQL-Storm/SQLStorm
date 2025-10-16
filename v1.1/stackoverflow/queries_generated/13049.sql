-- {"query": "13049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2142, "output_tokens": 715} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        AVG(p.Score) AS AvgPostScore,
        MAX(ph.CreationDate) AS LastActivityDate
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
    WHERE 
        u.LastAccessDate > CURRENT_DATE - INTERVAL '6 months'
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopContributors AS (
    SELECT 
        UserId,
        DisplayName,
        Reputation,
        TotalPosts,
        QuestionsAsked,
        AnswersGiven,
        AvgPostScore,
        LastActivityDate,
        ROW_NUMBER() OVER (ORDER BY TotalPosts DESC, AvgPostScore DESC) AS Rank
    FROM 
        UserActivity
    WHERE 
        TotalPosts > 0
)
SELECT 
    tc.DisplayName,
    tc.Reputation,
    tc.TotalPosts,
    tc.QuestionsAsked,
    tc.AnswersGiven,
    tc.AvgPostScore,
    tc.LastActivityDate,
    COUNT(DISTINCT ph.Id) AS TotalEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
    SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS PostClosed,
    STRING_AGG(DISTINCT pt.Name, ', ') FILTER (WHERE pt.Name IS NOT NULL) AS PostTypesContributed,
    (
        SELECT 
            COUNT(*) 
        FROM 
            Badges b 
        WHERE 
            b.UserId = tc.UserId AND b.Class = 1
    ) AS GoldBadges
FROM 
    TopContributors tc
JOIN 
    Posts p ON tc.UserId = p.OwnerUserId
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 10)
LEFT JOIN 
    PostTypes pt ON p.PostTypeId = pt.Id
WHERE 
    tc.Rank <= 10
GROUP BY 
    tc.UserId, tc.DisplayName, tc.Reputation, tc.TotalPosts, tc.QuestionsAsked, tc.AnswersGiven, tc.AvgPostScore, tc.LastActivityDate
ORDER BY 
    tc.TotalPosts DESC, tc.AvgPostScore DESC;
