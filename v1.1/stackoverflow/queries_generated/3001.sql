-- {"query": "3001.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1552} 
WITH AnswerCounts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        p.AnswerCount,
        p.FavoriteCount,
        p.CommentCount,
        p.ClosedDate,
        p.ContentLicense,
        ut.Name AS PostTypeName,
        ARRAY_LENGTH(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount,
        COALESCE(u.Reputation, 0) AS UserReputation,
        CASE WHEN u.Reputation >= 2000 THEN true ELSE false END AS IsReputableUser,
        bd.BadgeCount,
        -- Subquery: count of 'Gold' badges per user
        (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = p.OwnerUserId AND b2.Class = 1) AS GoldBadgeCount,
        -- Subquery: latest badge date for user
        (SELECT MAX(b3.Date) FROM Badges b3 WHERE b3.UserId = p.OwnerUserId) AS LastBadgeDate
    FROM
        Posts p
        JOIN PostTypes ut ON p.PostTypeId = ut.Id
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT
                b.UserId,
                COUNT(*) AS BadgeCount
            FROM Badges b
            GROUP BY b.UserId
        ) bd ON bd.UserId = p.OwnerUserId
    WHERE
        p.PostTypeId = 1 -- Questions only
),
ActivityStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        p.Score,
        p.ClosedDate,
        p.ContentLicense,
        ut.Name AS PostTypeName,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) AS TagCount,
        u.Reputation AS UserReputation,
        CASE WHEN u.Reputation >= 2000 THEN true ELSE false END AS IsReputableUser,
        bd.BadgeCount,
        (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = p.OwnerUserId AND b2.Class = 1) AS GoldBadgeCount,
        (SELECT MAX(b3.Date) FROM Badges b3 WHERE b3.UserId = p.OwnerUserId) AS LastBadgeDate
    FROM
        Posts p
        JOIN PostTypes ut ON p.PostTypeId = ut.Id
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT
                b.UserId,
                COUNT(*) AS BadgeCount
            FROM Badges b
            GROUP BY b.UserId
        ) bd ON bd.UserId = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
),
LastActivePosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.LastActivityDate,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName,
        u.Reputation,
        b.BadgeCount,
        (SELECT MAX(b3.Date) FROM Badges b3 WHERE b3.UserId = p.OwnerUserId) AS LastBadgeDate
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            b.UserId,
            COUNT(*) AS BadgeCount
        FROM Badges b
        GROUP BY b.UserId
    ) b ON b.UserId = p.OwnerUserId
    WHERE p.LastActivityDate > NOW() - INTERVAL '180 days'
)
SELECT
    ac.PostId,
    ac.Title,
    ac.Tags,
    ac.CreationDate,
    ac.Score,
    ac.ViewCount,
    ac.OwnerUserId,
    ac.UserReputation,
    ac.IsReputableUser,
    ac.BadgeCount,
    ac.GoldBadgeCount,
    ac.LastBadgeDate,
    (
        SELECT COUNT(*) FROM Posts a
        WHERE a.ParentId = ac.PostId
    ) AS AnswerCountForQuestion,
    (
        SELECT AVG(votes_count) FROM (
            SELECT COUNT(*) AS votes_count
            FROM Votes v
            WHERE v.PostId = ac.PostId
            GROUP BY v.UserId
        ) sub
    ) AS AverageVotesPerUser,
    (
        SELECT COUNT(*) FROM PostLinks pl
        WHERE pl.PostId = ac.PostId AND pl.LinkTypeId = 1 -- Linked
    ) AS LinkedPostsCount,
    (
        SELECT COUNT(*) FROM PostLinks pl
        WHERE pl.RelatedPostId = ac.PostId AND pl.LinkTypeId = 1
    ) AS ReferencedByCount,
    (
        SELECT COUNT(*) FROM Comments c
        WHERE c.PostId = ac.PostId
    ) AS CommentCountTotal,
    (
        SELECT MAX(c.CreationDate) FROM Comments c
        WHERE c.PostId = ac.PostId
    ) AS LastCommentDate,
    CASE WHEN ac.BadgeCount > 0 THEN true ELSE false END AS HasBadges,
    CASE WHEN ac.UserReputation >= 2000 THEN true ELSE false END AS ReputableUserFlag,
    (EXISTS (
        SELECT 1 FROM Posts pa WHERE pa.ParentId = ac.PostId
    )) AS HasAnswers,
    (ac.LastBadgeDate IS NOT NULL) AS HasRecentBadge,
    -- Conditional predicate with complex expression
    CASE
        WHEN ac.Score > 10 AND ac.ViewCount > 1000 AND ac.TagCount > 3 THEN 'High engagement'
        WHEN ac.Score BETWEEN 0 AND 10 AND ac.ViewCount BETWEEN 500 AND 1000 THEN 'Moderate engagement'
        ELSE 'Low engagement'
    END AS EngagementLevel,
    -- String expression with concatenation and NULL handling
    COALESCE(ac.OwnerUserId::text, 'Unknown') || ' - ' || COALESCE(ac.DisplayName, 'Anonymous') AS OwnerInfo,
    -- Set operation: union with last active posts
    -- Note: union with LastActivePosts as subquery
    *
FROM
    AnswerCounts ac
UNION ALL
SELECT
    lap.PostId,
    lap.Title,
    NULL AS Tags,
    lap.CreationDate,
    lap.Score,
    lap.ViewCount,
    lap.OwnerUserId,
    NULL AS UserReputation,
    NULL AS IsReputableUser,
    NULL AS BadgeCount,
    NULL AS GoldBadgeCount,
    lap.LastBadgeDate,
    NULL AS AnswerCountForQuestion,
    NULL AS AverageVotesPerUser,
    NULL AS LinkedPostsCount,
    NULL AS ReferencedByCount,
    NULL AS CommentCountTotal,
    NULL AS LastCommentDate,
    NULL AS HasBadges,
    NULL AS ReputableUserFlag,
    NULL AS HasAnswers,
    NULL AS HasRecentBadge,
    NULL AS EngagementLevel,
    COALESCE(lap.OwnerUserId::text, 'Unknown') || ' - ' || COALESCE(lap.DisplayName, 'Anonymous') AS OwnerInfo,
    NULL -- Placeholder for union
FROM LastActivePosts lap
ORDER BY
    CreationDate DESC
LIMIT 100;