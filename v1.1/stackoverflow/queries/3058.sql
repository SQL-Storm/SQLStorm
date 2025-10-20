WITH PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.Title,
        p.Tags,
        p.Body,
        p.LastActivityDate,
        p.FavoriteCount,
        p.ClosedDate,
        p.ContentLicense,
        u.Reputation,
        u.Location,
        u.DisplayName,
        array_length(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '<>'), 1) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM
        Posts p
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
),
AnswerCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(a.Id) AS AnswerCount
    FROM
        Posts p
        LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    GROUP BY
        p.Id
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.RevisionGUID,
        ph.UserDisplayName,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS RecentRevisionRank
    FROM
        PostHistory ph
)
SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(ac.AnswerCount, 0) AS AnswerCount,
    p.CommentCount,
    p.Title,
    p.Tags,
    p.Body,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ClosedDate,
    p.ContentLicense,
    COALESCE(rb.GoldBadges, 0) AS GoldBadges,
    COALESCE(rb.SilverBadges, 0) AS SilverBadges,
    COALESCE(rb.BronzeBadges, 0) AS BronzeBadges,
    u.Reputation,
    u.Location,
    u.DisplayName,
    array_length(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '<>'), 1) AS TagCount,
    -- Last 5 upvote types (names) as comma-separated
    (SELECT string_agg(vt.Name, ', ' ORDER BY v.CreationDate DESC)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name LIKE '%Up%'
     LIMIT 5) AS RecentUpVotes,
    -- Latest revision comment if any
    (SELECT psh2.Comment
     FROM RecentPostHistory psh2
     WHERE psh2.PostId = p.Id AND psh2.RecentRevisionRank = 1 AND psh2.PostHistoryTypeId IN (4,5,6,7,8,9)
     ORDER BY psh2.CreationDate DESC
     LIMIT 1) AS LastRevisionComment,
    -- Complex predicate with string expression, NULL handling, and custom calculation
    CASE
        WHEN p.OwnerUserId IS NULL THEN 'Anonymous'
        WHEN u.Reputation > 1000 AND p.Score > 10 THEN 'HighRepHighScore'
        WHEN p.OwnerUserId IS NULL AND p.CreationDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year') THEN 'NewUserAnonymous'
        ELSE 'Regular'
    END AS UserStatus,
    -- Count of linked posts of type 3 (duplicates)
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
    -- Optional outer join with answer posts: count of answers for this post (from joined alias 'a' aggregated)
    COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS TotalAnswers,
    -- set operator example: union with posts tagged 'sql' and 'database'
    (SELECT string_agg(DISTINCT t.TagName, ', ')
     FROM (SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR (length(p.Tags) - 2)), '<>')) AS TagName) t
     WHERE t.TagName ILIKE '%sql%'
     UNION
     SELECT 'database') AS RelevantTags
FROM
    Posts p
LEFT JOIN
    Users u ON p.OwnerUserId = u.Id
LEFT JOIN
    AnswerCounts ac ON p.Id = ac.PostId
LEFT JOIN
    UserBadgeSummary rb ON u.Id = rb.UserId
LEFT JOIN
    Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
LEFT JOIN
    RecentPostHistory psh ON p.Id = psh.PostId
WHERE
    p.PostTypeId = 1
    AND (p.Title IS NOT NULL OR p.Body IS NOT NULL)
    AND (p.OwnerUserId IS NOT NULL OR p.OwnerUserId = -1)
    AND EXISTS (
        SELECT 1 FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId IN (2,3)
    )
GROUP BY
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.CommentCount,
    p.Title,
    p.Tags,
    p.Body,
    p.LastActivityDate,
    p.FavoriteCount,
    p.ClosedDate,
    p.ContentLicense,
    u.Reputation,
    u.Location,
    u.DisplayName,
    ac.AnswerCount,
    rb.GoldBadges,
    rb.SilverBadges,
    rb.BronzeBadges
ORDER BY
    p.CreationDate DESC
LIMIT 100;