-- {"query": "53023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 831} 
WITH TopTags AS (
    SELECT t.Id AS TagId, t.TagName, t.Count AS TagCount,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 1000
    LIMIT 50
),
UserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
           COUNT(DISTINCT p.Id) AS PostCount,
           SUM(p.Score) AS TotalScore,
           AVG(p.ViewCount) AS AvgViewCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesReceived
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserComments AS (
    SELECT c.UserId,
           COUNT(c.Id) AS CommentCount,
           AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.UserId
),
PostHistoryAnalysis AS (
    SELECT ph.PostId,
           COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,7,8,9) THEN 1 END) AS EditCount,
           MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
TagUserActivity AS (
    SELECT tt.TagId, ua.UserId,
           COUNT(DISTINCT p.Id) AS PostsInTag,
           SUM(p.Score) AS ScoreInTag
    FROM TopTags tt
    JOIN Posts p ON p.Tags LIKE CONCAT('%<', (SELECT TagName FROM Tags WHERE Id = tt.TagId), '>%')
    JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
    WHERE p.CreationDate >= '2020-01-01'
    GROUP BY tt.TagId, ua.UserId
    HAVING COUNT(DISTINCT p.Id) > 5
)
SELECT ua.UserId, ua.DisplayName, ua.Reputation, ua.PostCount, ua.TotalScore, ua.AvgViewCount,
       ua.QuestionCount, ua.AnswerCount, ua.UpvotesReceived,
       ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
       uc.CommentCount, uc.AvgCommentScore,
       tt.TagName, tua.PostsInTag, tua.ScoreInTag,
       pha.EditCount, pha.LastEditDate,
       ROW_NUMBER() OVER (PARTITION BY tt.TagId ORDER BY tua.ScoreInTag DESC) AS RankInTag
FROM UserActivity ua
JOIN UserBadges ub ON ua.UserId = ub.UserId
JOIN UserComments uc ON ua.UserId = uc.UserId
JOIN TagUserActivity tua ON ua.UserId = tua.UserId
JOIN TopTags tt ON tua.TagId = tt.TagId
JOIN Posts p ON ua.UserId = p.OwnerUserId AND p.PostTypeId = 1
JOIN PostHistoryAnalysis pha ON p.Id = pha.PostId
WHERE tt.TagRank <= 10
AND ua.Reputation > 50000
ORDER BY tt.TagRank, RankInTag
LIMIT 1000;