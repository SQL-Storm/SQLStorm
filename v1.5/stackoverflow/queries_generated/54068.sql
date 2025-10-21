-- {"query": "54068.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-oss-20b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2048, "output_tokens": 966} 
WITH UserStats AS (
    SELECT u.Id,
           u.Reputation,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS ACount,
           SUM(p.Score) AS TotalScore,
           SUM(CASE 
                   WHEN v.VoteTypeId = 2 THEN 1
                   WHEN v.VoteTypeId = 3 THEN -1
                   ELSE 0
               END) AS VoteSum,
           COUNT(b.Id) AS BadgesCount
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.Reputation
),
Ranked AS (
    SELECT us.*,
           ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) AS Rank
    FROM UserStats us
),
WithTags AS (
    SELECT r.Id,
           r.Reputation,
           r.QCount,
           r.ACount,
           r.TotalScore,
           r.VoteSum,
           r.BadgesCount,
           r.Rank,
           r.QCount + r.ACount AS TotalPosts,
           COALESCE(t.TagName, 'no tag') AS TopTag
    FROM Ranked r
    LEFT JOIN (
        SELECT p.OwnerUserId, t.TagName, COUNT(*) AS TagCnt
        FROM Posts p
        JOIN Tags t ON t.TagName = ANY(string_to_array(p.Tags, '>'))
        WHERE p.PostTypeId = 1
        GROUP BY p.OwnerUserId, t.TagName
        ORDER BY TagCnt DESC
        LIMIT 1
    ) t ON t.OwnerUserId = r.Id
)
SELECT *
FROM WithTags
WHERE Rank <= 100
ORDER BY TotalScore DESC, Reputation DESC;