-- {"query": "2075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 569} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(b.BadgeCount, 0) AS BadgeCount,
        COALESCE(p.PostCount, 0) AS PostCount,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        COALESCE(v.VoteCount, 0) AS VoteCount,
        RANK() OVER (ORDER BY COALESCE(b.BadgeCount, 0) DESC, COALESCE(p.PostCount, 0) DESC) AS UserRank
    FROM Users u
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) b ON u.Id = b.UserId
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCount
        FROM Posts
        WHERE PostTypeId IN (1, 2)
        GROUP BY OwnerUserId
    ) p ON u.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) c ON u.Id = c.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS VoteCount
        FROM Votes
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ) v ON u.Id = v.UserId
),
MaxBadges AS (
    SELECT
        MAX(BadgeCount) AS MaxBadgeCount
    FROM UserActivity
),
LinkAnalysis AS (
    SELECT DISTINCT
        pl.PostId,
        STRING_AGG(t.TagName, ', ') AS AggregateTagNames
    FROM PostLinks pl
    JOIN Posts p ON pl.RelatedPostId = p.Id
    JOIN UNNEST(
        STRING_TO_ARRAY(
            SUBSTRING(p.Tags, 2, CHAR_LENGTH(p.Tags) - 2),
            '><'
        )
    ) AS TagArray(tid) ON TRUE
    JOIN Tags t ON t.TagName = tid
    GROUP BY pl.PostId
)
SELECT ua.UserId, ua.DisplayName, ua.BadgeCount, ua.PostCount,
       ua.CommentCount, ua.VoteCount, MaxBadges.MaxBadgeCount,
       COALESCE(la.AggregateTagNames, 'No Tags Linked') AS Tags,
       CASE
           WHEN ua.BadgeCount = MaxBadges.MaxBadgeCount THEN 'Top Badge Holder'
           ELSE 'Regular User'
       END AS Status
FROM UserActivity ua
JOIN MaxBadges ON 1 = 1
LEFT JOIN LinkAnalysis la ON ua.UserId = la.PostId
WHERE ua.BadgeCount > 0;
