WITH UsersMaxReputation AS (
    SELECT
        Id AS UserId,
        MAX(Reputation) OVER() AS MaxReputation
    FROM Users
),
Top5Posters AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS PostCount
    FROM Posts
    WHERE PostTypeId IN (1, 2)
    GROUP BY OwnerUserId
    ORDER BY COUNT(*) DESC
    LIMIT 5
),
AggregatedVotes AS (
    SELECT
        p.Id AS PostId,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id
),
LinkedPosts AS (
    SELECT DISTINCT
        pl.PostId,
        MAX(pl.CreationDate) OVER(PARTITION BY pl.PostId) AS LatestLinkDate
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    CASE WHEN u.Id = umr.UserId THEN 'Max Reputation' ELSE 'Standard User' END AS UserType,
    COALESCE(CAST(STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS VARCHAR), 'No Tags') AS TagsContributed,
    COALESCE(a.UpVotes - a.DownVotes, 0) AS NetVotes,
    COALESCE(lp.LatestLinkDate, TIMESTAMP '1900-01-01') AS LatestPostLinkDate,
    COALESCE(badges.BadgeCount, 0) AS TotalBadges
FROM Users u
LEFT JOIN UsersMaxReputation umr ON u.Id = umr.UserId
LEFT JOIN Top5Posters tp ON u.Id = tp.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT TRIM(value) AS TagName
    FROM (
        -- convert tags string like '<tag1><tag2>' into rows in a dialect-agnostic way without set-returning functions
        SELECT CASE
                 WHEN p.Tags IS NULL OR p.Tags = '' THEN NULL
                 ELSE elem
               END AS value
        FROM (
            -- split tags into array elements in a dialect-agnostic way: use a simple replace + split approach
            SELECT
                -- normalize by removing leading < and trailing > if present
                CASE
                    WHEN LEFT(p.Tags,1) = '<' AND RIGHT(p.Tags,1) = '>' THEN SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2)
                    ELSE p.Tags
                END AS normalized_tags
        ) norm
        CROSS JOIN LATERAL (
            -- split normalized_tags on '><' by emulating array unnest using a recursive CTE compatible pattern
            WITH RECURSIVE split(pos, rest, elem) AS (
                SELECT
                    1,
                    norm.normalized_tags,
                    CASE WHEN norm.normalized_tags = '' THEN NULL
                         WHEN POSITION('><' IN norm.normalized_tags) = 0 THEN norm.normalized_tags
                         ELSE SUBSTRING(norm.normalized_tags FROM 1 FOR POSITION('><' IN norm.normalized_tags)-1)
                    END
                UNION ALL
                SELECT
                    pos + 1,
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN ''
                        ELSE SUBSTRING(rest FROM POSITION('><' IN rest) + 2)
                    END,
                    CASE
                        WHEN POSITION('><' IN rest) = 0 THEN NULL
                        ELSE SUBSTRING(rest FROM 1 FOR POSITION('><' IN rest)-1)
                    END
                FROM split
                WHERE rest <> '' AND POSITION('><' IN rest) > 0
            )
            SELECT elem FROM split WHERE elem IS NOT NULL
        ) s(elem)
    ) x
    WHERE value IS NOT NULL AND value <> ''
) t ON p.Id IS NOT NULL
LEFT JOIN AggregatedVotes a ON p.Id = a.PostId
LEFT JOIN LinkedPosts lp ON p.Id = lp.PostId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
) badges ON u.Id = badges.UserId
WHERE u.CreationDate > DATE '2020-01-01'
  AND (tp.OwnerUserId IS NOT NULL OR (a.UpVotes IS NOT NULL OR a.DownVotes IS NOT NULL))
GROUP BY u.Id, u.DisplayName, UserType, a.UpVotes, a.DownVotes, lp.LatestLinkDate, badges.BadgeCount, umr.UserId
ORDER BY NetVotes DESC, u.DisplayName;