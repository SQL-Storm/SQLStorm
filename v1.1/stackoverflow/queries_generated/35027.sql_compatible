WITH
TopTags AS (
    SELECT t.Id AS TagId, t.TagName, t.Count
    FROM Tags t
    ORDER BY t.Count DESC
    LIMIT 10
),
RecentActiveUsers AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
           u.LastAccessDate
    FROM Users u
    WHERE u.LastAccessDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY
      AND u.Reputation > 1000
),
PopularQuestions AS (
    SELECT p.Id AS QuestionId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
           p.Title, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
      AND p.Score > 5
      AND p.ViewCount > 500
),
TaggedQuestions AS (
    SELECT pq.QuestionId, pq.OwnerUserId, pq.CreationDate, pq.Score, pq.ViewCount,
           pq.Title, tt.TagName
    FROM PopularQuestions pq
    JOIN TopTags tt
      ON pq.Tags LIKE '%' || '<' || tt.TagName || '>' || '%'
),
AnswerStats AS (
    SELECT p.ParentId AS QuestionId, COUNT(*) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore, MAX(p.Score) AS MaxAnswerScore
    FROM Posts p
    WHERE p.PostTypeId = 2
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
    GROUP BY p.ParentId
),
QuestionCommentStats AS (
    SELECT c.PostId AS QuestionId, COUNT(*) AS CommentCount,
           AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    WHERE c.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
      AND c.PostId IN (SELECT QuestionId FROM PopularQuestions)
    GROUP BY c.PostId
),
BadgeCounts AS (
    SELECT b.UserId, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserVoteStats AS (
    SELECT v.UserId, 
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Votes v
    WHERE v.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '90' DAY
      AND v.UserId IS NOT NULL
    GROUP BY v.UserId
),
FinalAggregate AS (
    SELECT
        tq.QuestionId,
        tq.Title,
        tq.TagName,
        u.UserId AS UserId,
        u.DisplayName,
        u.Reputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        us.UpvotesGiven,
        us.DownvotesGiven,
        tq.Score AS QuestionScore,
        tq.ViewCount,
        a.AnswerCount,
        a.AvgAnswerScore,
        a.MaxAnswerScore,
        cs.CommentCount,
        cs.AvgCommentScore,
        u.LastAccessDate
    FROM TaggedQuestions tq
    LEFT JOIN RecentActiveUsers u
      ON tq.OwnerUserId = u.UserId
    LEFT JOIN BadgeCounts bc
      ON bc.UserId = u.UserId
    LEFT JOIN UserVoteStats us
      ON us.UserId = u.UserId
    LEFT JOIN AnswerStats a
      ON a.QuestionId = tq.QuestionId
    LEFT JOIN QuestionCommentStats cs
      ON cs.QuestionId = tq.QuestionId
    WHERE u.UserId IS NOT NULL
    GROUP BY
        tq.QuestionId,
        tq.Title,
        tq.TagName,
        u.UserId,
        u.DisplayName,
        u.Reputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        us.UpvotesGiven,
        us.DownvotesGiven,
        tq.Score,
        tq.ViewCount,
        a.AnswerCount,
        a.AvgAnswerScore,
        a.MaxAnswerScore,
        cs.CommentCount,
        cs.AvgCommentScore,
        u.LastAccessDate
)
SELECT *
FROM FinalAggregate
ORDER BY Reputation DESC, ViewCount DESC, AvgAnswerScore DESC
LIMIT 100;