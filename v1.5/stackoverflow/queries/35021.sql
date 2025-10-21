-- {"query": "35021.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 741} 
WITH TopUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, COUNT(p.Id) AS TotalPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 50
),
UserVotes AS (
    SELECT p.OwnerUserId AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesReceived
    FROM Posts p
    JOIN Votes v ON v.PostId = p.Id
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND p.PostTypeId IN (1,2)
    GROUP BY p.OwnerUserId
),
BadgeSummary AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY b.UserId
),
MostEditedPosts AS (
    SELECT ph.PostId, COUNT(*) AS NumEdits
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
      AND ph.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
    GROUP BY ph.PostId
    HAVING COUNT(*) > 10
),
TopTags AS (
    SELECT p.OwnerUserId AS UserId,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName
    FROM Posts p
    WHERE p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '1 year'
      AND p.PostTypeId = 1
),
UserTagCounts AS (
    SELECT UserId, TagName, COUNT(*) AS TagPosts
    FROM TopTags
    GROUP BY UserId, TagName
),
TopUserTag AS (
    SELECT DISTINCT ON (UserId)
        UserId, TagName, TagPosts
    FROM UserTagCounts
    ORDER BY UserId, TagPosts DESC
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.TotalPosts,
    uv.UpvotesReceived,
    uv.DownvotesReceived,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    tut.TagName AS TopTag,
    tut.TagPosts AS TopTagPosts,
    COALESCE((
        SELECT COUNT(*)
        FROM MostEditedPosts mep
        JOIN Posts p ON mep.PostId = p.Id
        WHERE p.OwnerUserId = tu.UserId
    ), 0) AS HighlyEditedPosts
FROM TopUsers tu
LEFT JOIN UserVotes uv ON tu.UserId = uv.UserId
LEFT JOIN BadgeSummary bs ON tu.UserId = bs.UserId
LEFT JOIN TopUserTag tut ON tu.UserId = tut.UserId
ORDER BY tu.Reputation DESC, tu.TotalPosts DESC
LIMIT 50;