-- {"query": "53042.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1084} 
WITH ParsedTags AS (
    SELECT p.Id AS PostId,
           unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserActivity AS (
    SELECT u.Id AS UserId,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
           SUM(p.Score) AS TotalScore,
           AVG(p.ViewCount) AS AvgViewCount,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id
    HAVING COUNT(DISTINCT p.Id) > 50
),
BadgeSummary AS (
    SELECT b.UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
VoteAnalysis AS (
    SELECT v.PostId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
           SUM(CASE WHEN v.VoteTypeId IN (4, 12) THEN 1 ELSE 0 END) AS Flags
    FROM Votes v
    GROUP BY v.PostId
),
CommentStats AS (
    SELECT c.PostId,
           COUNT(c.Id) AS CommentCount,
           AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
PostHistoryMetrics AS (
    SELECT ph.PostId,
           COUNT(ph.Id) AS EditCount,
           MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY ph.PostId
    HAVING COUNT(ph.Id) > 5
),
TagPopularity AS (
    SELECT pt.TagName,
           COUNT(DISTINCT pt.PostId) AS TaggedQuestions,
           AVG(va.Upvotes - va.Downvotes) AS AvgNetVotes
    FROM ParsedTags pt
    JOIN VoteAnalysis va ON pt.PostId = va.PostId
    GROUP BY pt.TagName
    HAVING COUNT(DISTINCT pt.PostId) > 100
),
TopUsersPerTag AS (
    SELECT tp.TagName,
           u.Id AS TopUserId,
           SUM(p.Score) AS TagScore,
           ROW_NUMBER() OVER (PARTITION BY tp.TagName ORDER BY SUM(p.Score) DESC) AS UserRank
    FROM TagPopularity tp
    JOIN ParsedTags pt ON tp.TagName = pt.TagName
    JOIN Posts p ON pt.PostId = p.Id OR (p.ParentId = pt.PostId AND p.PostTypeId = 2)
    JOIN Users u ON p.OwnerUserId = u.Id
    GROUP BY tp.TagName, u.Id
),
CombinedMetrics AS (
    SELECT ua.UserId,
           ua.QuestionCount,
           ua.AnswerCount,
           ua.TotalScore,
           ua.AvgViewCount,
           ua.LastPostDate,
           bs.GoldBadges,
           bs.SilverBadges,
           bs.BronzeBadges,
           COUNT(DISTINCT pl.RelatedPostId) AS LinkedPosts,
           SUM(va.Upvotes) AS TotalUpvotes,
           SUM(va.Downvotes) AS TotalDownvotes,
           AVG(cs.CommentCount) AS AvgCommentsPerPost,
           MAX(phm.EditCount) AS MaxEditsOnPost
    FROM UserActivity ua
    LEFT JOIN BadgeSummary bs ON ua.UserId = bs.UserId
    LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN VoteAnalysis va ON p.Id = va.PostId
    LEFT JOIN CommentStats cs ON p.Id = cs.PostId
    LEFT JOIN PostHistoryMetrics phm ON p.Id = phm.PostId
    GROUP BY ua.UserId, ua.QuestionCount, ua.AnswerCount, ua.TotalScore, ua.AvgViewCount, ua.LastPostDate,
             bs.GoldBadges, bs.SilverBadges, bs.BronzeBadges
)
SELECT cm.*,
       (SELECT TagName FROM TopUsersPerTag tut WHERE tut.TopUserId = cm.UserId AND tut.UserRank = 1 LIMIT 1) AS TopTag
FROM CombinedMetrics cm
WHERE cm.TotalScore > 1000 AND cm.GoldBadges >= 1
ORDER BY cm.TotalScore DESC, cm.LastPostDate DESC
LIMIT 100;