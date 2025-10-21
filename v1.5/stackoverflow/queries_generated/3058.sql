-- {"query": "3058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1145} 
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
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>'), 1) AS TagCount,
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
    ps.PostId,
    ps.PostTypeId,
    ps.OwnerUserId,
    ps.CreationDate,
    ps.Score,
    ps.ViewCount,
    ac.AnswerCount,
    ps.CommentCount,
    ps.Title,
    ps.Tags,
    ps.Body,
    ps.LastActivityDate,
    ps.FavoriteCount,
    ps.ClosedDate,
    ps.ContentLicense,
    rb.GoldBadges,
    rb.SilverBadges,
    rb.BronzeBadges,
    u.Reputation,
    u.Location,
    u.DisplayName,
    ps.TagCount,
    -- Last 5 answer votes with set operation and conditional logic
    (SELECT string_agg(CAST(vt.Name AS varchar), ', ' ORDER BY v.CreationDate DESC)
     FROM Votes v
     JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
     WHERE v.PostId = p.Id AND vt.Name LIKE '%Up%'
     LIMIT 5) AS RecentUpVotes,
    -- Latest revision comment if any
    (SELECT pc.Comment
     FROM RecentPostHistory psh
     WHERE psh.PostId = p.Id AND psh.RecentRevisionRank = 1 AND psh.PostHistoryTypeId IN (4,5,6,7,8,9)
     ORDER BY psh.CreationDate DESC LIMIT 1) AS LastRevisionComment,
    -- Complex predicate with string expression, NULL handling, and custom calculation
    CASE WHEN ps.OwnerUserId IS NULL THEN 'Anonymous'
         WHEN u.Reputation > 1000 AND ps.Score > 10 THEN 'HighRepHighScore'
         WHEN ps.OwnerUserId IS NULL AND ps.CreationDate > NOW() - INTERVAL '1 year' THEN 'NewUserAnonymous'
         ELSE 'Regular' END AS UserStatus,
    -- Count of linked posts of type 3 (duplicates)
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinks,
    -- Optional outer join with answer posts
    a.AnswerCount AS TotalAnswers,
    -- set operator example: union with posts tagged 'sql' and 'database'
    (SELECT string_agg(DISTINCT t.TagName, ', ')
     FROM unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '<>')) AS t(TagName)
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
ORDER BY
    p.CreationDate DESC
LIMIT 100;