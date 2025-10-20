WITH HighRepUsers AS (
    SELECT Id, DisplayName, Reputation, UpVotes, DownVotes
    FROM Users
    WHERE Reputation > 10000
      AND CreationDate BETWEEN TIMESTAMP '2010-01-01' AND TIMESTAMP '2023-12-31'
),
ActivePosts AS (
    SELECT p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.Tags,
           COUNT(c.Id) AS CommentCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRank
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1' YEAR)
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.Tags
    HAVING AVG(p.Score) > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
),
GoldBadgeUsers AS (
    SELECT UserId, COUNT(Id) AS GoldBadges
    FROM Badges
    WHERE Class = 1
      AND Name LIKE '%Legendary%'
    GROUP BY UserId
    HAVING COUNT(Id) >= 3
)
SELECT hru.DisplayName, hru.Reputation, ap.Title, ap.Score, ap.ViewCount,
       ap.CommentCount, ap.Upvotes, gbu.GoldBadges,
       (SELECT COUNT(ph.Id)
        FROM PostHistory ph
        WHERE ph.PostId = ap.Id
          AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
       (SELECT STRING_AGG(tg.TagName, ', ')
        FROM (
          SELECT TRIM(BOTH ',' FROM t.tag) AS TagName
          FROM regexp_split_to_table(
                 regexp_replace(regexp_replace(ap.Tags, '<', '', 'g'), '>', ',', 'g'),
                 ',') AS t(tag)
        ) sub
        JOIN Tags tg ON tg.TagName = sub.TagName
        WHERE tg.IsModeratorOnly = FALSE
       ) AS CleanedTags
FROM HighRepUsers hru
JOIN ActivePosts ap ON hru.Id = ap.OwnerUserId
JOIN GoldBadgeUsers gbu ON hru.Id = gbu.UserId
JOIN PostLinks pl ON ap.Id = pl.PostId AND pl.LinkTypeId = 3
WHERE ap.PostRank <= 5
  AND ap.Tags LIKE '%<sql>%'
  AND EXISTS (
    SELECT 1
    FROM PostHistory ph
    WHERE ph.PostId = ap.Id
      AND ph.PostHistoryTypeId = 10
      AND ph.CreationDate BETWEEN TIMESTAMP '2022-01-01' AND TIMESTAMP '2023-12-31'
  )
GROUP BY hru.DisplayName, hru.Reputation, hru.Id, ap.Id, ap.OwnerUserId, ap.Title, ap.Score, ap.ViewCount, ap.CommentCount, ap.Upvotes, ap.Tags, ap.PostRank, gbu.UserId, gbu.GoldBadges, pl.PostId, pl.LinkTypeId
ORDER BY hru.Reputation DESC, ap.Score DESC
LIMIT 100;