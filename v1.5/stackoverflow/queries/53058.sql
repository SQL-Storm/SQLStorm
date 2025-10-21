-- {"query": "53058.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 778} 
WITH TopUsers AS (
    SELECT u.Id AS UserId, u.Reputation,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           SUM(p.Score) AS TotalScore,
           SUM(p.ViewCount) AS TotalViews
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 100
),
UserBadges AS (
    SELECT b.UserId, COUNT(*) AS GoldBadges, SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges b
    WHERE b.Class IN (1, 2)
    GROUP BY b.UserId
),
UserVotes AS (
    SELECT p.OwnerUserId AS UserId, SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
),
PopularTags AS (
    SELECT t.TagName, t.Count AS TagPopularity
    FROM Tags t
    ORDER BY t.Count DESC
    LIMIT 10
),
UserTags AS (
    SELECT p.OwnerUserId AS UserId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS Tag,
           COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY p.OwnerUserId, Tag
),
TopUserTags AS (
    SELECT ut.UserId, ut.Tag, ut.TagCount,
           ROW_NUMBER() OVER (PARTITION BY ut.UserId ORDER BY ut.TagCount DESC) AS TagRank
    FROM UserTags ut
    JOIN PopularTags pt ON ut.Tag = pt.TagName
),
EditsPerUser AS (
    SELECT ph.UserId, COUNT(*) AS EditCount,
           COUNT(DISTINCT ph.PostId) AS EditedPosts
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY ph.UserId
)
SELECT tu.UserId, tu.Reputation, tu.QuestionCount, tu.AnswerCount, tu.TotalScore, tu.TotalViews,
       COALESCE(ub.GoldBadges, 0) AS GoldBadges, COALESCE(ub.SilverBadges, 0) AS SilverBadges,
       COALESCE(uv.UpVotesReceived, 0) AS UpVotesReceived, COALESCE(uv.DownVotesReceived, 0) AS DownVotesReceived,
       COALESCE(tut.Tag, 'None') AS TopTag, COALESCE(tut.TagCount, 0) AS TopTagCount,
       COALESCE(epu.EditCount, 0) AS EditCount, COALESCE(epu.EditedPosts, 0) AS EditedPosts,
       RANK() OVER (ORDER BY tu.Reputation DESC) AS ReputationRank
FROM TopUsers tu
LEFT JOIN UserBadges ub ON tu.UserId = ub.UserId
LEFT JOIN UserVotes uv ON tu.UserId = uv.UserId
LEFT JOIN TopUserTags tut ON tu.UserId = tut.UserId AND tut.TagRank = 1
LEFT JOIN EditsPerUser epu ON tu.UserId = epu.UserId
ORDER BY tu.Reputation DESC
LIMIT 100;