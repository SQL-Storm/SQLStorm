-- {"query": "58017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "deepseek-r1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2033, "output_tokens": 1191} 

WITH ActiveUsers AS (
    SELECT u.Id, u.Reputation, u.CreationDate, u.DisplayName, 
           COUNT(DISTINCT p.Id) AS PostCount,
           COUNT(DISTINCT c.Id) AS CommentCount,
           COUNT(DISTINCT v.Id) AS VoteCount,
           COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1 AND p.CreationDate >= '2020-01-01'
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.CreationDate >= '2020-01-01'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2,3) AND v.CreationDate >= '2020-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Class IN (1,2,3) AND b.Date >= '2020-01-01'
    WHERE u.Reputation > 10000 
      AND u.ProfileImageUrl IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM PostHistory ph 
          WHERE ph.UserId = u.Id 
            AND ph.PostHistoryTypeId IN (2,5,7) 
            AND ph.CreationDate >= '2020-01-01'
      )
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) >= 100 
       AND COUNT(DISTINCT c.Id) >= 50 
       AND COUNT(DISTINCT v.Id) >= 200
)
SELECT au.DisplayName, au.Reputation, au.PostCount, au.CommentCount, au.VoteCount, au.BadgeCount,
       RANK() OVER (ORDER BY au.BadgeCount DESC) AS BadgeRank,
       (SELECT STRING_AGG(TagName, ', ' ORDER BY Count DESC LIMIT 5) 
        FROM Tags t 
        WHERE t.Id IN (
            SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))::int
            FROM Posts p 
            WHERE p.OwnerUserId = au.Id AND p.PostTypeId = 1
        )) AS TopTags,
       (SELECT COUNT(*) FROM PostLinks pl 
        WHERE pl.LinkTypeId = 3 
          AND pl.PostId IN (
              SELECT Id FROM Posts WHERE OwnerUserId = au.Id AND PostTypeId = 1
          )) AS DuplicateClosures
FROM ActiveUsers au
JOIN Badges b ON au.Id = b.UserId AND b.Class = 1
WHERE au.BadgeCount > (SELECT AVG(BadgeCount) FROM ActiveUsers)
ORDER BY au.Reputation DESC, au.PostCount DESC
LIMIT 100;
