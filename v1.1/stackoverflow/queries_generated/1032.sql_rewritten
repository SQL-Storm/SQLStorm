-- {"query": "1032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 616} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT 
        UserId, 
        DisplayName, 
        Reputation, 
        BadgeCount, 
        UpVotesCount, 
        DownVotesCount,
        QuestionCount,
        AnswerCount,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, UpVotesCount DESC) AS Rank
    FROM 
        UserStats
),
RecentPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        STRING_AGG(t.TagName, ', ') AS Tags
    FROM 
        Posts p
    JOIN 
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount
),
UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT r.PostId) AS RecentPostCount,
        SUM(r.ViewCount) AS TotalViews
    FROM 
        Users u
    JOIN 
        RecentPosts r ON u.Id = r.OwnerUserId
    GROUP BY 
        u.Id, u.DisplayName
)

SELECT 
    tu.DisplayName,
    tu.Reputation,
    tu.BadgeCount,
    tu.UpVotesCount,
    tu.DownVotesCount,
    ups.RecentPostCount,
    ups.TotalViews,
    COALESCE(ROUND((tu.UpVotesCount * 1.0 / NULLIF(tu.DownVotesCount, 0) * 100), 2), 0) AS UpvoteToDownvoteRatio
FROM 
    TopUsers tu
LEFT JOIN 
    UserPostStats ups ON tu.UserId = ups.UserId
WHERE 
    tu.Rank <= 10
ORDER BY 
    tu.Rank;