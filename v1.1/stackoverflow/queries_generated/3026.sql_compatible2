WITH TagUsageCTE AS (
    SELECT
        t.TagName,
        t.Count,
        p.Title AS PostTitle,
        p.CreationDate AS PostCreationDate,
        u.DisplayName AS OwnerDisplayName,
        CASE WHEN v.VoteTypeId IN (2,3) THEN
            CASE WHEN v.VoteTypeId = 2 THEN 'Upvote' ELSE 'Downvote' END
        ELSE NULL END AS VoteType,
        ROW_NUMBER() OVER (PARTITION BY t.TagName ORDER BY p.CreationDate DESC) AS RecentUsageRank
    FROM
        Tags t
        LEFT JOIN Posts p ON t.WikiPostId = p.Id
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE
        t.IsModeratorOnly = FALSE
        AND p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
),
FilteredTagUsage AS (
    SELECT
        TagName,
        Count,
        PostTitle,
        OwnerDisplayName,
        VoteType,
        RecentUsageRank
    FROM
        TagUsageCTE
    WHERE
        RecentUsageRank = 1
),
UserTopTags AS (
    SELECT
        t.TagName,
        t.Count,
        t.Id AS TagId
    FROM Tags t
    WHERE t.IsModeratorOnly = FALSE
    ORDER BY t.Count DESC
    LIMIT 5
),
UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        STRING_AGG(utt.TagName, ', ') AS TopTags,
        MAX(u.LastAccessDate) AS LastAccess
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
        LEFT JOIN UserTopTags utt ON 1=1
    GROUP BY
        u.Id,
        u.Reputation
),
PostActivity AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        (
            SELECT
                COUNT(*) FROM Comments c WHERE c.PostId = p.Id
        ) AS CommentCount,
        p.ViewCount,
        p.Tags,
        p.LastActivityDate,
        p.LastEditDate,
        FIRST_VALUE(p.LastActivityDate) OVER (PARTITION BY p.Id ORDER BY p.LastEditDate DESC NULLS LAST) AS LastActive,
        p.OwnerUserId
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
),
ComplexJoin AS (
    SELECT
        pa.PostId,
        pa.Title,
        pa.CreationDate,
        pa.Score,
        pa.AnswerCount,
        pa.CommentCount,
        pa.ViewCount,
        pa.Tags,
        ua.Reputation,
        ua.TopTags,
        ua.LastAccess,
        lu.Title AS LastRelatedPostTitle,
        l.LinkTypeId,
        CASE WHEN l.LinkTypeId = 3 THEN 'Duplicate' ELSE 'Linked' END AS LinkTypeName,
        vt.Name AS VoteTypeName
    FROM
        PostActivity pa
        LEFT JOIN UserReputation ua ON pa.OwnerUserId = ua.UserId
        LEFT JOIN PostLinks l ON pa.PostId = l.PostId AND l.LinkTypeId IN (1,3)
        LEFT JOIN Posts lu ON l.RelatedPostId = lu.Id
        LEFT JOIN Votes v ON pa.PostId = v.PostId
        LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE
        (vt.Name = 'Upvote' OR vt.Name IS NULL)
        AND pa.ViewCount > 100
)
SELECT
    c.PostId,
    c.Title,
    c.CreationDate,
    c.Score,
    c.AnswerCount,
    c.CommentCount,
    c.ViewCount,
    c.Tags,
    c.Reputation,
    c.TopTags,
    c.LastAccess,
    c.LastRelatedPostTitle,
    c.LinkTypeName,
    CASE WHEN c.Score + c.AnswerCount * 2 - c.CommentCount * 0.5 > 10 THEN 'Highly Engaged'
         WHEN c.ViewCount > 1000 AND c.Reputation > 1000 THEN 'Influencer'
         ELSE 'Average' END AS EngagementLevel,
    STRING_AGG(TU.TagName || ': ' || COALESCE(TU.VoteType, ''), '; ' ORDER BY TU.RecentUsageRank) AS LatestTagVotes
FROM
    ComplexJoin c
    LEFT JOIN FilteredTagUsage TU ON c.Tags LIKE '%' || TU.TagName || '%'
GROUP BY
    c.PostId,
    c.Title,
    c.CreationDate,
    c.Score,
    c.AnswerCount,
    c.CommentCount,
    c.ViewCount,
    c.Tags,
    c.Reputation,
    c.TopTags,
    c.LastAccess,
    c.LastRelatedPostTitle,
    c.LinkTypeName
ORDER BY
    c.CreationDate DESC
LIMIT 100;