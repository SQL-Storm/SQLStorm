-- {"query": "53081.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 1043} 
WITH ActiveUsers AS (
    SELECT u.Id AS UserId, u.Reputation, COUNT(DISTINCT p.Id) AS PostCount, SUM(p.Score) AS TotalScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.CreationDate > '2010-01-01' AND p.CreationDate > '2010-01-01'
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 50 AND SUM(p.Score) > 100
),
UserBadges AS (
    SELECT UserId, COUNT(Id) AS GoldBadges, SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM Badges
    WHERE Class IN (1, 2) AND TagBased = TRUE
    GROUP BY UserId
),
UserVotes AS (
    SELECT v.UserId, COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven, COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE v.CreationDate > '2010-01-01' AND p.PostTypeId IN (1, 2)
    GROUP BY v.UserId
),
TaggedQuestions AS (
    SELECT p.Id, p.OwnerUserId, tag AS TagName, p.Score, COUNT(c.Id) AS CommentCount
    FROM Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2010-01-01'
    GROUP BY p.Id, p.OwnerUserId, tag, p.Score
),
UserTagStats AS (
    SELECT au.UserId, tq.TagName, SUM(tq.Score) AS TotalTagScore, AVG(tq.CommentCount) AS AvgComments, COUNT(tq.Id) AS QuestionCount
    FROM ActiveUsers au
    JOIN TaggedQuestions tq ON tq.OwnerUserId = au.UserId
    GROUP BY au.UserId, tq.TagName
    HAVING COUNT(tq.Id) > 10
),
RankedTags AS (
    SELECT uts.UserId, uts.TagName, uts.TotalTagScore, uts.AvgComments, uts.QuestionCount,
           ROW_NUMBER() OVER (PARTITION BY uts.UserId ORDER BY uts.TotalTagScore DESC) AS TagRank
    FROM UserTagStats uts
),
PostHistoryStats AS (
    SELECT ph.PostId, COUNT(ph.Id) AS EditCount, MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9) AND ph.CreationDate > '2010-01-01'
    GROUP BY ph.PostId
),
LinkedPosts AS (
    SELECT pl.PostId, COUNT(DISTINCT pl.RelatedPostId) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
)
SELECT au.UserId, u.DisplayName, au.Reputation, au.PostCount, au.TotalScore,
       COALESCE(ub.GoldBadges, 0) AS GoldBadges, COALESCE(ub.SilverBadges, 0) AS SilverBadges,
       COALESCE(uv.UpvotesGiven, 0) AS UpvotesGiven, COALESCE(uv.DownvotesGiven, 0) AS DownvotesGiven,
       rt.TagName AS TopTag, rt.TotalTagScore AS TopTagScore, rt.AvgComments AS TopTagAvgComments, rt.QuestionCount AS TopTagQuestionCount,
       AVG(phs.EditCount) AS AvgEditsPerPost, MAX(phs.LastEdit) AS LatestEdit,
       SUM(COALESCE(lp.DuplicateCount, 0)) AS TotalDuplicates
FROM ActiveUsers au
JOIN Users u ON u.Id = au.UserId
LEFT JOIN UserBadges ub ON ub.UserId = au.UserId
LEFT JOIN UserVotes uv ON uv.UserId = au.UserId
LEFT JOIN RankedTags rt ON rt.UserId = au.UserId AND rt.TagRank = 1
LEFT JOIN Posts p ON p.OwnerUserId = au.UserId
LEFT JOIN PostHistoryStats phs ON phs.PostId = p.Id
LEFT JOIN LinkedPosts lp ON lp.PostId = p.Id
GROUP BY au.UserId, u.DisplayName, au.Reputation, au.PostCount, au.TotalScore,
         ub.GoldBadges, ub.SilverBadges, uv.UpvotesGiven, uv.DownvotesGiven,
         rt.TagName, rt.TotalTagScore, rt.AvgComments, rt.QuestionCount
ORDER BY au.Reputation DESC
LIMIT 100;