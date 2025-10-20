-- {"query": "43007.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 615} 

WITH UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(u.Reputation) AS Reputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate > NOW() - INTERVAL '90 days'
    GROUP BY u.Id, u.DisplayName
),
TopContributors AS (
    SELECT
        ua.*,
        RANK() OVER (ORDER BY ua.TotalPosts DESC, ua.Reputation DESC) AS Rank
    FROM UserActivity ua
    WHERE ua.TotalPosts > 10
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        ph.CreationDate AS LastEditDate,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS rn
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 6)
    WHERE p.PostTypeId = 1 AND p.CreationDate > NOW() - INTERVAL '30 days'
)
SELECT
    tc.DisplayName,
    tc.TotalQuestions,
    tc.TotalAnswers,
    tc.TotalBadges,
    rq.Title,
    rq.CreationDate AS QuestionCreated,
    rq.LastEditDate AS LastEdited,
    rq.Score,
    rq.ViewCount,
    rq.Tags,
    COUNT(DISTINCT v.UserId) AS TotalVotes
FROM TopContributors tc
JOIN RecentQuestions rq ON tc.Id = rq.OwnerUserId
LEFT JOIN Votes v ON rq.Id = v.PostId
WHERE tc.Rank <= 10 AND rq.rn = 1
GROUP BY tc.DisplayName, tc.TotalQuestions, tc.TotalAnswers, tc.TotalBadges, rq.Title, rq.CreationDate, rq.LastEditDate, rq.Score, rq.ViewCount, rq.Tags
ORDER BY tc.TotalPosts DESC, rq.Score DESC;
