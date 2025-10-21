-- {"query": "35066.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 649} 
WITH RecentHighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
      AND CreationDate > NOW() - INTERVAL '1 year'
),
TopTags AS (
    SELECT t.TagName, SUM(t.Count) AS TagTotal
    FROM Tags t
    GROUP BY t.TagName
    ORDER BY TagTotal DESC
    LIMIT 10
),
UserTopQuestions AS (
    SELECT 
        p.OwnerUserId,
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        ARRAY(
            SELECT tag FROM UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) tag
        ) AS TagArray
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Questions only
      AND p.Score > 5
      AND p.ViewCount > 1000
      AND p.CreationDate > NOW() - INTERVAL '6 months'
),
BadgeCounts AS (
    SELECT u.Id AS UserId, 
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges,
    q.PostId, q.Title, q.Score AS QuestionScore, q.ViewCount, 
    t.TagName AS TopTag,
    SUM(vs.UpVotes) OVER (PARTITION BY u.Id) AS TotalUpVotesForUser,
    SUM(vs.DownVotes) OVER (PARTITION BY u.Id) AS TotalDownVotesForUser,
    COUNT(DISTINCT c.Id) AS TotalCommentsOnTopQuestions
FROM RecentHighReputationUsers u
LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
LEFT JOIN UserTopQuestions q ON q.OwnerUserId = u.Id
LEFT JOIN LATERAL (
    SELECT tag FROM UNNEST(q.TagArray) tag 
    INNER JOIN TopTags t ON t.TagName = tag
    LIMIT 1
) t ON TRUE
LEFT JOIN (
    SELECT p.OwnerUserId, 
           SUM(p.UpVotes) AS UpVotes, 
           SUM(p.DownVotes) AS DownVotes
    FROM Posts p
    GROUP BY p.OwnerUserId
) vs ON vs.OwnerUserId = u.Id
LEFT JOIN Comments c ON c.PostId = q.PostId
WHERE t.TagName IS NOT NULL
GROUP BY u.Id, u.DisplayName, u.Reputation, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, q.PostId, q.Title, q.Score, q.ViewCount, t.TagName
ORDER BY u.Reputation DESC, q.ViewCount DESC
LIMIT 100;