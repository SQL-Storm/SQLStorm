-- {"query": "3809.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1335} 
WITH 
-- CTE to aggregate basic user activity
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(p.PostCount,0) AS TotalPosts,
        COALESCE(a.AnswerCount,0) AS TotalAnswers,
        COALESCE(q.QuestionCount,0) AS TotalQuestions,
        COALESCE(b.BadgeCount,0) AS TotalBadges,
        COALESCE(v.UpVoteCount,0) - COALESCE(v.DownVoteCount,0) AS NetVoteScore,
        MAX(p.LatestPostDate) OVER (PARTITION BY u.Id) AS LatestPostDate
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount,
               MAX(CreationDate) AS LatestPostDate
        FROM Posts
        GROUP BY OwnerUserId
    ) p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
        FROM Posts
        GROUP BY OwnerUserId
    ) a ON a.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId,
               SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount
        FROM Posts
        GROUP BY OwnerUserId
    ) q ON q.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON b.UserId = u.Id
    LEFT JOIN (
        SELECT v.PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
        FROM Votes v
        JOIN Posts p ON p.Id = v.PostId
        WHERE p.OwnerUserId = u.Id
        GROUP BY v.PostId
    ) v ON v.PostId = p.OwnerUserId
),

-- CTE to get top tags per user based on post tags
UserTopTags AS (
    SELECT 
        ua.UserId,
        t.TagName,
        COUNT(*) AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM UserActivity ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(trim(both '<>' from p.Tags), '><')) AS TagName
    ) t
    WHERE p.Tags IS NOT NULL
    GROUP BY ua.UserId, t.TagName
),

-- CTE to fetch the most recent comment per user with NULL handling
UserRecentComments AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(c.Text, '(No comment)') AS RecentComment,
        c.CreationDate
    FROM Users u
    LEFT JOIN LATERAL (
        SELECT Text, CreationDate
        FROM Comments c
        WHERE c.UserId = u.Id
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) c ON TRUE
),

-- CTE to compute a composite activity score
UserScore AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalAnswers,
        ua.TotalQuestions,
        ua.TotalBadges,
        ua.NetVoteScore,
        (ua.Reputation * 0.5
         + ua.TotalPosts * 10
         + ua.TotalAnswers * 15
         + ua.TotalQuestions * 20
         + ua.TotalBadges * 25
         + ua.NetVoteScore * 5) AS CompositeScore
    FROM UserActivity ua
),

-- Final aggregation with set operator to include inactive users (no posts, no badges)
ActiveUsers AS (
    SELECT 
        us.UserId,
        u.DisplayName,
        us.CompositeScore,
        utc.TagName AS TopTag,
        urc.RecentComment,
        us.LatestPostDate
    FROM UserScore us
    JOIN Users u ON u.Id = us.UserId
    LEFT JOIN UserTopTags utc ON utc.UserId = us.UserId AND utc.TagRank = 1
    LEFT JOIN UserRecentComments urc ON urc.UserId = us.UserId
    WHERE us.TotalPosts > 0
),
InactiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        0 AS CompositeScore,
        NULL AS TopTag,
        '(No activity)' AS RecentComment,
        NULL AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE p.Id IS NULL AND b.Id IS NULL
)

SELECT *
FROM ActiveUsers
UNION ALL
SELECT *
FROM InactiveUsers
ORDER BY CompositeScore DESC NULLS LAST, DisplayName;