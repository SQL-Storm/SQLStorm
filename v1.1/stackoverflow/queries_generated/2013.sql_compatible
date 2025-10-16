WITH RecentActiveUsers AS (
    SELECT Id, DisplayName, Reputation,
           ROW_NUMBER() OVER (ORDER BY LastAccessDate DESC) AS RecentUserRank
    FROM Users
    WHERE LastAccessDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 YEAR'
),
TaggedQuestions AS (
    /* normalize Tags string into rows is dialect-specific; here approximate by splitting on '><' */
    SELECT p.Id AS PostId, p.OwnerUserId AS UserId, p.Title,
           (SELECT COUNT(*) FROM (
                SELECT UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS tag
           ) t) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.Tags
),
TopCommenters AS (
    SELECT c.UserId, u.DisplayName, COUNT(c.Id) AS CommentCount
    FROM Comments c
    JOIN Users u ON c.UserId = u.Id
    GROUP BY c.UserId, u.DisplayName
    HAVING COUNT(c.Id) > 50
),
RecordedTagsPerUser AS (
    SELECT UserId, COUNT(*) AS RecordedTagCount
    FROM TaggedQuestions
    GROUP BY UserId
)
SELECT u.Id, u.DisplayName, COALESCE(ta.RecordedTagCount, 0) AS RecordedTagCount,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
       COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes
FROM Users u
LEFT JOIN RecordedTagsPerUser ta ON ta.UserId = u.Id
LEFT JOIN Votes v ON v.UserId = u.Id
WHERE u.Id IN (SELECT ra.Id FROM RecentActiveUsers ra WHERE ra.RecentUserRank <= 100)
GROUP BY u.Id, u.DisplayName, ta.RecordedTagCount
ORDER BY UpVotes DESC, DownVotes ASC;