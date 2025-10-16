-- {"query": "1032.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1677} 

WITH RecentQuestions AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CreationDate,
           COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
      AND p.ViewCount IS NOT NULL
),
UserBadges AS (
    SELECT b.UserId,
           COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges
    FROM Badges b
    WHERE b.Date > NOW() - INTERVAL '2 years'
    GROUP BY b.UserId
),
UserStats AS (
    SELECT u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location,
           COALESCE(b.GoldBadges, 0) AS GoldBadges,
           COALESCE(b.SilverBadges, 0) AS SilverBadges,
           COALESCE(b.BronzeBadges, 0) AS BronzeBadges,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS TotalQuestions,
           (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS TotalAnswers
    FROM Users u
    LEFT JOIN UserBadges b ON u.Id = b.UserId
    WHERE u.Reputation > 1000
),
AnswerAggregates AS (
    SELECT p.ParentId AS QuestionId,
           COUNT(*) AS AnswerCount,
           AVG(p.Score) AS AvgAnswerScore,
           MAX(p.Score) AS MaxAnswerScore,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
TopTags AS (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS TagName,
           p.Id AS PostId,
           p.Score
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TagScores AS (
    SELECT t.TagName,
           COUNT(*) AS TagUsageCount,
           AVG(t.Score) AS AvgTagScore
    FROM TopTags t
    GROUP BY t.TagName
    HAVING COUNT(*) > 50
),
QualifiedQuestions AS (
    SELECT rq.Id, rq.Title, rq.OwnerUserId, rq.Score, rq.ViewCount, rq.CreationDate, 
           ag.AnswerCount, ag.AvgAnswerScore, ag.MaxAnswerScore, ag.TotalUpVotes, ag.TotalDownVotes,
           ts.TagName, ts.AvgTagScore, ts.TagUsageCount
    FROM RecentQuestions rq
    LEFT JOIN AnswerAggregates ag ON rq.Id = ag.QuestionId
    LEFT JOIN TopTags tt ON rq.Id = tt.PostId
    LEFT JOIN TagScores ts ON tt.TagName = ts.TagName
    WHERE ag.AnswerCount IS NOT NULL
      AND ts.TagUsageCount IS NOT NULL
),
UserWithQuestions AS (
    SELECT us.Id AS UserId, us.DisplayName, us.Reputation,
           us.GoldBadges, us.SilverBadges, us.BronzeBadges,
           COUNT(q.Id) AS RecentQuestionCount,
           AVG(q.Score) AS AvgQuestionScore,
           AVG(q.ViewCount) AS AvgViewCount,
           AVG(q.AvgAnswerScore) AS AvgAnswerScore,
           MAX(q.MaxAnswerScore) AS MaxAnswerScore,
           STRING_AGG(DISTINCT q.TagName, ', ' ORDER BY q.TagName) AS Tags
    FROM UserStats us
    LEFT JOIN QualifiedQuestions q ON us.Id = q.OwnerUserId
    GROUP BY us.Id, us.DisplayName, us.Reputation, us.GoldBadges, us.SilverBadges, us.BronzeBadges
    HAVING COUNT(q.Id) > 2
),
BadgedUsersWithComments AS (
    SELECT uwq.UserId, uwq.DisplayName, uwq.Reputation, uwq.GoldBadges, uwq.SilverBadges, uwq.BronzeBadges,
           uwq.RecentQuestionCount, uwq.AvgQuestionScore, uwq.AvgViewCount, uwq.AvgAnswerScore, uwq.MaxAnswerScore, uwq.Tags,
           COALESCE(c.CommentCount, 0) AS CommentCount,
           ROW_NUMBER() OVER (ORDER BY uwq.Reputation DESC, uwq.GoldBadges DESC, uwq.AvgQuestionScore DESC) AS RankByReputation
    FROM UserWithQuestions uwq
    LEFT JOIN (
        SELECT c.UserId, COUNT(*) AS CommentCount
        FROM Comments c
        WHERE c.CreationDate > NOW() - INTERVAL '6 months'
        GROUP BY c.UserId
    ) c ON uwq.UserId = c.UserId
),
ClosedQuestionsWithReasons AS (
    SELECT ph.PostId AS QuestionId, crt.Name AS CloseReason, ph.CreationDate AS CloseDate
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
    WHERE ph.PostHistoryTypeId = 10
      AND ph.CreationDate > NOW() - INTERVAL '1 year'
),
ComplexScores AS (
    SELECT buw.UserId,
           COUNT(DISTINCT cq.QuestionId) AS RecentlyClosedQuestions,
           AVG(buw.AvgQuestionScore) * 0.5 + 
           AVG(buw.AvgAnswerScore) * 0.3 + 
           LOG(1 + buw.GoldBadges)::float * 2 +
           LOG(1 + buw.SilverBadges)::float * 1.5 +
           LOG(1 + buw.BronzeBadges)::float AS UserComplexScore
    FROM BadgedUsersWithComments buw
    LEFT JOIN ClosedQuestionsWithReasons cq ON buw.UserId = (SELECT OwnerUserId FROM Posts p WHERE p.Id = cq.QuestionId)
    GROUP BY buw.UserId
)
SELECT buw.UserId, buw.DisplayName, buw.Reputation, buw.GoldBadges, buw.SilverBadges, buw.BronzeBadges,
       buw.RecentQuestionCount, buw.AvgQuestionScore, buw.AvgViewCount, buw.AvgAnswerScore, buw.MaxAnswerScore,
       buw.Tags, buw.CommentCount, cs.RecentlyClosedQuestions, cs.UserComplexScore,
       CASE 
           WHEN cs.UserComplexScore > 100 THEN 'Expert'
           WHEN cs.UserComplexScore BETWEEN 50 AND 100 THEN 'Intermediate'
           ELSE 'Beginner'
       END AS UserLevel,
       CONCAT(
           'Reputation: ', buw.Reputation, ' | Questions: ', buw.RecentQuestionCount,
           ' | Comments: ', buw.CommentCount, ' | Badges: ', buw.GoldBadges, '-', buw.SilverBadges, '-', buw.BronzeBadges
       ) AS UserSummary
FROM BadgedUsersWithComments buw
JOIN ComplexScores cs ON buw.UserId = cs.UserId
WHERE buw.RecentQuestionCount > 5
  AND cs.UserComplexScore > 10
ORDER BY cs.UserComplexScore DESC, buw.Reputation DESC
LIMIT 50;
