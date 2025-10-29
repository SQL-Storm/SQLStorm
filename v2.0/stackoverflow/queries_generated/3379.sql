-- {"query": "3379.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2571} 
WITH UserStats AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COUNT(DISTINCT p.Id)                               AS TotalPosts,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
           SUM(COALESCE(p.Score, 0))                         AS TotalScore,
           MAX(p.CreationDate)                               AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
), BadgeStats AS (
    SELECT b.UserId,
           COUNT(*)                                          AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END)      AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END)      AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END)      AS BronzeBadges,
           STRING_AGG(DISTINCT b.Name, ',')                  AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
), TopTags AS (
    SELECT u.Id                              AS UserId,
           t.TagName,
           ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY COUNT(*) DESC) AS rn
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    CROSS JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' FROM p.Tags), '><')) AS tag
    ) AS tags
    JOIN Tags t ON t.TagName = tags.tag
    GROUP BY u.Id, t.TagName
), CommentStats AS (
    SELECT c.UserId,
           COUNT(*)            AS CommentCount,
           MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
), VoteAgg AS (
    SELECT v.PostId,
           SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
)
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.TotalPosts,
       us.Questions,
       us.Answers,
       us.TotalScore,
       COALESCE(bs.BadgeCount, 0)  AS BadgeCount,
       COALESCE(bs.GoldBadges, 0)  AS GoldBadges,
       COALESCE(bs.SilverBadges, 0) AS SilverBadges,
       COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
       bs.BadgeNames,
       COALESCE(cs.CommentCount, 0) AS CommentCount,
       us.LastPostDate,
       cs.LastCommentDate,
       (SELECT COUNT(*) FROM Posts p2
        WHERE p2.OwnerUserId = us.Id
          AND p2.CreationDate > DATE '2023-01-01')                     AS RecentPosts2023,
       (SELECT STRING_AGG(t.TagName, ', ')
        FROM (SELECT tt.TagName
              FROM TopTags tt
              WHERE tt.UserId = us.Id AND tt.rn <= 3) t)               AS Top3Tags,
       RANK() OVER (ORDER BY us.Reputation DESC)                       AS ReputationRank,
       (SELECT MAX(vu.UpVotes)
        FROM VoteAgg vu
        WHERE vu.PostId IN (SELECT p3.Id FROM Posts p3 WHERE p3.OwnerUserId = us.Id)
       )                                                               AS MaxUpVotesOnUserPosts
FROM UserStats us
LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
LEFT JOIN CommentStats cs ON cs.UserId = us.Id
WHERE (us.Reputation > 1000 OR us.TotalScore > 50)
  AND (us.LastPostDate IS NOT NULL OR cs.LastCommentDate IS NOT NULL)
ORDER BY us.Reputation DESC
LIMIT 100
UNION ALL
SELECT u.Id,
       u.DisplayName,
       u.Reputation,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       0,
       NULL,
       0,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation >= 500
EXCEPT
SELECT us.Id,
       us.DisplayName,
       us.Reputation,
       us.TotalPosts,
       us.Questions,
       us.Answers,
       us.TotalScore,
       COALESCE(bs.BadgeCount, 0),
       COALESCE(bs.GoldBadges, 0),
       COALESCE(bs.SilverBadges, 0),
       COALESCE(bs.BronzeBadges, 0),
       bs.BadgeNames,
       COALESCE(cs.CommentCount, 0),
       us.LastPostDate,
       cs.LastCommentDate,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL,
       NULL
FROM UserStats us
LEFT JOIN BadgeStats bs ON bs.UserId = us.Id
LEFT JOIN CommentStats cs ON cs.UserId = us.Id
WHERE us.TotalPosts = 0;