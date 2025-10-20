-- {"query": "43074.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 573} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT ph.Id) AS TotalEdits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 2 THEN LENGTH(ph.Text) ELSE 0 END) AS TotalEditBodyLength,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotesReceived
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (2, 5)
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    LEFT JOIN 
        Votes v ON u.Id = v.UserId
    LEFT JOIN 
        VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY 
        u.Id
),
TopContributors AS (
    SELECT 
        ua.UserId,
        u.DisplayName,
        ua.TotalPosts,
        ua.TotalEdits,
        ua.TotalEditBodyLength,
        ua.TotalBadges,
        ua.TotalUpvotesReceived,
        ua.TotalDownvotesReceived,
        ROW_NUMBER() OVER (ORDER BY ua.TotalPosts DESC, ua.TotalEdits DESC) AS Rank
    FROM 
        UserActivity ua
    JOIN 
        Users u ON ua.UserId = u.Id
    WHERE 
        u.Reputation > 1000
)
SELECT 
    tc.UserId,
    tc.DisplayName,
    tc.TotalPosts,
    tc.TotalEdits,
    tc.TotalEditBodyLength,
    tc.TotalBadges,
    tc.TotalUpvotesReceived,
    tc.TotalDownvotesReceived,
    p.Title AS LastPostTitle,
    p.CreationDate AS LastPostCreationDate
FROM 
    TopContributors tc
LEFT JOIN 
    Posts p ON tc.UserId = p.OwnerUserId AND p.PostTypeId = 1
WHERE 
    tc.Rank <= 10
ORDER BY 
    tc.Rank;