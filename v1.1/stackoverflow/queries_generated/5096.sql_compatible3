WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        ROW_NUMBER() OVER (ORDER BY u.LastAccessDate DESC) AS rn
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.LastAccessDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserTopTags AS (
    SELECT 
        p.OwnerUserId AS UserId,
        t.TagName,
        COUNT(*) AS PostsWithTag,
        RANK() OVER (PARTITION BY p.OwnerUserId ORDER BY COUNT(*) DESC) AS tag_rank
    FROM Posts p
    JOIN (
        SELECT Id, regexp_split_to_table(substring(Tags FROM 2 FOR (LENGTH(Tags) - 2)), '><') AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL
    ) t ON t.Id = p.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, t.TagName
),
AnswerStats AS (
    SELECT 
        p.ParentId AS QuestionId,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(*) AS AnswerCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
RecentUserBadges AS (
    SELECT 
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    GROUP BY b.UserId
)
SELECT 
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.CreationDate,
    rau.LastAccessDate,
    rau.TotalPosts,
    r.BadgesAwarded,
    r.DaysSinceLastBadge,
    utt.TagName AS TopTag,
    utt.PostsWithTag,
    q.Id AS LastActiveQuestionId,
    q.Title AS LastActiveQuestionTitle,
    asq.AvgAnswerScore,
    asq.AnswerCount,
    COALESCE(clr.Name, 'No Close Reason') AS LastCloseReason,
    CASE 
        WHEN rau.Reputation >= 20000 THEN 'Legend'
        WHEN rau.Reputation >= 10000 THEN 'Expert'
        WHEN rau.Reputation >= 1000 THEN 'Established'
        ELSE 'Rookie'
    END AS ReputationStatus,
    LENGTH(u.AboutMe) AS AboutMeLength,
    CASE WHEN q.ClosedDate IS NULL THEN 'Open' ELSE 'Closed' END AS QuestionStatus
FROM RecentActiveUsers rau
LEFT JOIN (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgesAwarded,
        EXTRACT(DAY FROM (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - MAX(b.Date))) AS DaysSinceLastBadge
    FROM Badges b
    GROUP BY b.UserId
) r ON r.UserId = rau.UserId
LEFT JOIN UserTopTags utt ON utt.UserId = rau.UserId AND utt.tag_rank = 1
LEFT JOIN Posts q ON q.OwnerUserId = rau.UserId AND q.PostTypeId = 1 AND q.CreationDate = (
    SELECT MAX(p2.CreationDate)
    FROM Posts p2
    WHERE p2.OwnerUserId = rau.UserId AND p2.PostTypeId = 1
)
LEFT JOIN AnswerStats asq ON asq.QuestionId = q.Id
LEFT JOIN PostHistory ph ON ph.PostId = q.Id AND ph.PostHistoryTypeId = 10
LEFT JOIN CloseReasonTypes clr ON CAST(clr.Id AS VARCHAR) = ph.Comment
LEFT JOIN Users u ON u.Id = rau.UserId
WHERE rau.rn <= 50
GROUP BY
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.CreationDate,
    rau.LastAccessDate,
    rau.TotalPosts,
    r.BadgesAwarded,
    r.DaysSinceLastBadge,
    utt.TagName,
    utt.PostsWithTag,
    q.Id,
    q.Title,
    asq.AvgAnswerScore,
    asq.AnswerCount,
    clr.Name,
    u.AboutMe,
    q.ClosedDate,
    rau.rn
ORDER BY rau.Reputation DESC, rau.TotalPosts DESC, rau.UserId;