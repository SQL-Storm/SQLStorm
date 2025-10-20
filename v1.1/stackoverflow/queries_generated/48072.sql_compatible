WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        MAX(p.CreationDate) AS LastPostCreationDate,
        MAX(c.CreationDate) AS LastCommentCreationDate,
        MAX(v.CreationDate) AS LastVoteCreationDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate > CAST('2010-01-01' AS timestamp)
    GROUP BY u.Id, u.DisplayName
),
HighReputationUsers AS (
    SELECT
        UserId
    FROM UserActivity
    WHERE TotalPosts > 1000 AND TotalVotes > 5000
),
RecentQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.AnswerCount,
        p.Score,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30' DAY)
                            AND CAST('2024-10-01 12:34:56' AS timestamp)
),
PopularTags AS (
    SELECT
        t.TagName,
        COUNT(p.Id) AS PostCount
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    WHERE t.Count > 10000
    GROUP BY t.TagName
    ORDER BY PostCount DESC
    LIMIT 10
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    rq.Title AS RecentQuestionTitle,
    pt.TagName AS PopularTag,
    CASE
        WHEN hru.UserId IS NOT NULL THEN 'High Reputation'
        ELSE 'Standard'
    END AS UserCategory
FROM UserActivity ua
JOIN RecentQuestions rq ON ua.UserId = rq.OwnerUserId
JOIN PopularTags pt ON pt.TagName = (
    SELECT t2.TagName
    FROM Posts p2
    JOIN Tags t2 ON p2.Tags LIKE '%' || t2.TagName || '%'
    WHERE p2.Id = rq.Id AND p2.PostTypeId = 1
    LIMIT 1
)
LEFT JOIN HighReputationUsers hru ON ua.UserId = hru.UserId
WHERE ua.TotalPosts > 500 AND ua.TotalVotes > 1000
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    rq.Title,
    rq.Id,
    rq.OwnerUserId,
    rq.CreationDate,
    rq.AnswerCount,
    rq.Score,
    pt.TagName,
    hru.UserId,
    ua.LastPostCreationDate
ORDER BY ua.TotalVotes DESC, ua.TotalPosts DESC, ua.LastPostCreationDate DESC
LIMIT 100;