-- {"query": "55060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 1058} 

WITH RECURSIVE TagHierarchy AS (
    SELECT t.Id, t.TagName, NULL::int AS ParentTagId, 0 AS Depth
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT c.Id, c.TagName, p.Id, p.Depth + 1
    FROM Tags c
    JOIN TagHierarchy p ON c.TagName LIKE p.TagName || '-%'
    WHERE c.IsModeratorOnly = 0
),
TopUsers AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS rn
    FROM Users u
    WHERE u.Reputation > 10000
),
UserBadges AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 3
                    WHEN b.Class = 2 THEN 2
                    ELSE 1 END) AS BadgeScore,
           COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBadgeCount
    FROM Badges b
    GROUP BY b.UserId
),
PostScore AS (
    SELECT p.Id,
           p.PostTypeId,
           p.OwnerUserId,
           p.CreationDate,
           p.Score + COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0) AS NetScore,
           COALESCE(p.ViewCount,0) AS Views,
           COALESCE(p.FavoriteCount,0) AS Favorites,
           COALESCE(p.AnswerCount,0) AS Answers,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY (p.Score + COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) DESC) AS RankInUser
    FROM Posts p
    LEFT JOIN (
        SELECT PostId,
               SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
               SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        GROUP BY PostId
    ) v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1   -- questions only
),
RecentActivity AS (
    SELECT ph.PostId,
           MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS LastEdit,
           MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS ClosedOn,
           MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 12) AS DeletedOn
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.BadgeScore,
    ub.TagBadgeCount,
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    ps.NetScore,
    ps.Views,
    ps.Favorites,
    ps.Answers,
    ra.LastEdit,
    ra.ClosedOn,
    ra.DeletedOn,
    th.TagName AS RootTag,
    th.Depth AS TagDepth,
    COALESCE(plc.RelatedCount,0) AS LinkedPostCount,
    COALESCE(pd.DuplicateCount,0) AS DuplicatePostCount
FROM TopUsers u
JOIN UserBadges ub ON ub.UserId = u.Id
JOIN Posts p ON p.OwnerUserId = u.Id
JOIN PostScore ps ON ps.Id = p.Id
JOIN RecentActivity ra ON ra.PostId = p.Id
LEFT JOIN LATERAL (
    SELECT string_to_array(trim(both '<>' FROM p.Tags), '><')[1] AS RootTag
) rt ON TRUE
LEFT JOIN TagHierarchy th ON th.TagName = rt.RootTag
LEFT JOIN (
    SELECT pl.PostId, COUNT(*) AS RelatedCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1
    GROUP BY pl.PostId
) plc ON plc.PostId = p.Id
LEFT JOIN (
    SELECT pl.PostId, COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
) pd ON pd.PostId = p.Id
WHERE u.rn <= 100
  AND ps.RankInUser <= 5
ORDER BY u.Reputation DESC, ps.NetScore DESC, p.CreationDate DESC
LIMIT 500;
