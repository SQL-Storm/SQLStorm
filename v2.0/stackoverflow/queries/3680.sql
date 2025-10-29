-- {"query": "3680.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1752}
WITH UserStats AS (
    SELECT 
        u.Id                                         AS UserId,
        u.DisplayName,
        u.Reputation,
        COALESCE(p.PostCnt, 0)                        AS PostCount,
        COALESCE(b.BadgeCnt, 0)                       AS BadgeCount,
        COALESCE(v.UpVotes, 0)                        AS UpVoteSum,
        COALESCE(v.DownVotes, 0)                      AS DownVoteSum,

        (SELECT p2.Title
         FROM Posts p2
         WHERE p2.OwnerUserId = u.Id
         ORDER BY p2.CreationDate DESC
         LIMIT 1)                                    AS LatestPostTitle,

        (SELECT STRING_AGG(DISTINCT t.TagName, ',')
         FROM Tags t
         JOIN (
               SELECT DISTINCT UNNEST(STRING_TO_ARRAY(p.Tags, '><')) AS TagName
               FROM Posts p
               WHERE p.OwnerUserId = u.Id
         ) pt ON pt.TagName = t.TagName)             AS TagList
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS PostCnt
        FROM Posts
        WHERE OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ) p  ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCnt
        FROM Badges
        GROUP BY UserId
    ) b  ON b.UserId = u.Id
    LEFT JOIN (
        SELECT 
            p.OwnerUserId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ) v  ON v.OwnerUserId = u.Id
)

SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.PostCount,
    us.BadgeCount,
    us.UpVoteSum,
    us.DownVoteSum,
    us.LatestPostTitle,
    COALESCE(us.TagList, '')                     AS Tags,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.PostCount DESC) AS RankByReputation,
    CASE 
        WHEN (us.UpVoteSum + us.DownVoteSum) = 0 THEN NULL
        ELSE ROUND(100.0 * us.UpVoteSum 
                   / NULLIF(us.UpVoteSum + us.DownVoteSum,0), 2)
    END                                         AS UpVotePercent,
    CASE 
        WHEN us.LatestPostTitle IS NULL THEN 'NoPosts'
        ELSE 'HasPosts'
    END                                         AS PostPresence
FROM UserStats us
WHERE (us.Reputation > 10000 OR us.BadgeCount >= 5)
  AND (us.UpVoteSum - us.DownVoteSum) > 0

UNION ALL

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    0                                          AS PostCount,
    0                                          AS BadgeCount,
    0                                          AS UpVoteSum,
    0                                          AS DownVoteSum,
    NULL                                       AS LatestPostTitle,
    ''                                         AS Tags,
    NULL                                       AS RankByReputation,
    NULL                                       AS UpVotePercent,
    'Inactive'                                 AS PostPresence
FROM Users u
WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
  AND u.Reputation < 1000

ORDER BY RankByReputation NULLS LAST, Reputation DESC
OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;