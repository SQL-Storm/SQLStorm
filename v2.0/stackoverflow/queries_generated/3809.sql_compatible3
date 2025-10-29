WITH 
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
        p.LatestPostDate
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
        SELECT p2.OwnerUserId AS OwnerUserId,
               SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
               SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
        FROM Votes v
        JOIN Posts p2 ON p2.Id = v.PostId
        GROUP BY p2.OwnerUserId
    ) v ON v.OwnerUserId = u.Id
),

UserTopTags AS (
    SELECT 
        ua.UserId,
        tmap.TagName,
        COUNT(*) AS TagUsage,
        ROW_NUMBER() OVER (PARTITION BY ua.UserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM UserActivity ua
    JOIN Posts p ON p.OwnerUserId = ua.UserId
    JOIN (
        -- split tags string like '<tag1><tag2>' into rows using regexp_split_to_table for broad compatibility
        SELECT p2.Id AS PostId, regexp_split_to_table(trim(both '<>' FROM p2.Tags), '><') AS TagName
        FROM Posts p2
        WHERE p2.Tags IS NOT NULL
    ) tmap ON tmap.PostId = p.Id
    WHERE p.Tags IS NOT NULL
    GROUP BY ua.UserId, tmap.TagName
),

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

UserScore AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.TotalPosts,
        ua.TotalAnswers,
        ua.TotalQuestions,
        ua.TotalBadges,
        ua.NetVoteScore,
        ua.LatestPostDate,
        (ua.Reputation * 0.5
         + ua.TotalPosts * 10
         + ua.TotalAnswers * 15
         + ua.TotalQuestions * 20
         + ua.TotalBadges * 25
         + ua.NetVoteScore * 5) AS CompositeScore
    FROM UserActivity ua
),

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
    LEFT JOIN (
        SELECT UserId, TagName
        FROM (
            SELECT UserId, TagName,
                   ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsage DESC) AS rn
            FROM UserTopTags
        ) t
        WHERE rn = 1
    ) utc ON utc.UserId = us.UserId
    LEFT JOIN UserRecentComments urc ON urc.UserId = us.UserId
    WHERE us.TotalPosts > 0
),

InactiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        0::numeric AS CompositeScore,
        NULL::text AS TopTag,
        '(No activity)' AS RecentComment,
        NULL::timestamp AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE p.Id IS NULL AND b.Id IS NULL
)

SELECT UserId, DisplayName, CompositeScore, TopTag, RecentComment, LatestPostDate
FROM ActiveUsers
UNION ALL
SELECT UserId, DisplayName, CompositeScore, TopTag, RecentComment, LatestPostDate
FROM InactiveUsers
ORDER BY CompositeScore DESC NULLS LAST, DisplayName;