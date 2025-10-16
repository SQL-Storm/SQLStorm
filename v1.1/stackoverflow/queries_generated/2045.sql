-- {"query": "2045.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 656} 

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
    MAX(CASE WHEN u.Id = umr.UserId THEN 'Max Reputation' ELSE 'Standard User' END) AS UserType,
    COALESCE(CAST(STRING_AGG(t.TagName, ', ') WITHIN GROUP (ORDER BY t.TagName ASC) AS VARCHAR), 'No Tags') AS TagsContributed,
    COALESCE(a.UpVotes - a.DownVotes, 0) AS NetVotes,
    COALESCE(lp.LatestLinkDate, TIMESTAMP '1900-01-01') AS LatestPostLinkDate,
    COALESCE(badges.BadgeCount, 0) AS TotalBadges
FROM Users u
LEFT JOIN UsersMaxReputation umr ON u.Id = umr.UserId
LEFT JOIN Top5Posters tp ON u.Id = tp.OwnerUserId
LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM Unnest(SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><', 1)) AS t(TagName)
    WHERE p.Tags IS NOT NULL
) t ON true
LEFT JOIN AggregatedVotes a ON p.Id = a.PostId
LEFT JOIN LinkedPosts lp ON p.Id = lp.PostId
LEFT JOIN (
    SELECT UserId, COUNT(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
) badges ON u.Id = badges.UserId
WHERE u.CreationDate > '2020-01-01'
AND (tp.OwnerUserId IS NOT NULL OR a.NetVotes IS NOT NULL)
GROUP BY u.Id, u.DisplayName, a.UpVotes, a.DownVotes, lp.LatestLinkDate, badges.BadgeCount
ORDER BY NetVotes DESC, u.DisplayName;
