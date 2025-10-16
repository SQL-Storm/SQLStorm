-- {"query": "2081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 467} 

WITH RecentPosts AS (
    SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId
    FROM Posts p
    WHERE p.CreationDate > NOW() - INTERVAL '30 days' AND p.PostTypeId = 1
),
ActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, 
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
    FROM Users u
    WHERE u.LastAccessDate > NOW() - INTERVAL '30 days'
),
UserBadges AS (
    SELECT ub.UserId, COUNT(ub.Id) AS BadgeCount
    FROM Badges ub
    GROUP BY ub.UserId
),
TopTags AS (
    SELECT t.TagName, COUNT(pt.Id) AS TagUsage
    FROM Tags t
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, p.Id
        FROM Posts p
    ) pt ON t.TagName = pt.TagName
    GROUP BY t.TagName
    ORDER BY TagUsage DESC
    LIMIT 5
),
QuestionDetails AS (
    SELECT rp.Id AS QuestionId, rp.Title, au.DisplayName, au.Reputation, ub.BadgeCount, pt.TagName
    FROM RecentPosts rp
    JOIN ActiveUsers au ON rp.OwnerUserId = au.Id
    LEFT JOIN UserBadges ub ON au.Id = ub.UserId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(rp.Tags, 2, length(rp.Tags)-2), '><')) AS TagName
    ) pt ON pt.TagName IN (SELECT TagName FROM TopTags)
)
SELECT qd.QuestionId, qd.Title, qd.DisplayName, qd.Reputation,
       COALESCE(qd.BadgeCount, 0) AS BadgeCount, STRING_AGG(qd.TagName, ', ') AS Tags
FROM QuestionDetails qd
GROUP BY qd.QuestionId, qd.Title, qd.DisplayName, qd.Reputation, qd.BadgeCount
ORDER BY qd.Reputation DESC, qd.BadgeCount DESC;
