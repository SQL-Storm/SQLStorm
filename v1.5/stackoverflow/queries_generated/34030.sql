-- {"query": "34030.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1313} 

WITH RecentActiveUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, COUNT(p.Id) AS PostCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE u.LastAccessDate > NOW() - INTERVAL '180 days'
      AND p.CreationDate > NOW() - INTERVAL '360 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(p.Id) > 5
),
TopTags AS (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) AS TagName, COUNT(*) AS Uses
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY TagName
    ORDER BY Uses DESC
    LIMIT 10
),
UserBadgeStats AS (
    SELECT b.UserId, 
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
QuestionAnswerStats AS (
    SELECT q.Id AS QuestionId, q.Title, q.CreationDate, q.Score AS QuestionScore, q.ViewCount,
           COUNT(a.Id) AS AnswerCount,
           AVG(a.Score) AS AvgAnswerScore,
           MAX(a.Score) AS MaxAnswerScore,
           SUM(COALESCE(vs.UpVotes,0)) AS SumAnswerUpVotes,
           SUM(COALESCE(vs.DownVotes,0)) AS SumAnswerDownVotes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN (
       SELECT p.Id, 
              (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId=2) AS UpVotes,
              (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId=3) AS DownVotes
       FROM Posts p
       WHERE p.PostTypeId = 2
    ) vs ON vs.Id = a.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate > NOW() - INTERVAL '2 years'
    GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount
    HAVING COUNT(a.Id) > 2
),
PostLinkDuplicates AS (
    SELECT pl.PostId, pl.RelatedPostId, COUNT(*) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId, pl.RelatedPostId
    HAVING COUNT(*) > 0
),
RecentClosedQuestions AS (
    SELECT ph.PostId, ph.CreationDate AS ClosedDate, cr.Name AS CloseReason, COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenCount
    FROM PostHistory ph
    JOIN CloseReasonTypes cr ON cr.Id = CAST(ph.Comment AS smallint)
    WHERE ph.PostHistoryTypeId IN (10, 11)
      AND ph.CreationDate > NOW() - INTERVAL '1 year'
    GROUP BY ph.PostId, ph.CreationDate, cr.Name
),
UserActivitySummary AS (
    SELECT u.Id,
           COALESCE(pc.QuestionCount,0) AS QuestionsPosted,
           COALESCE(ac.AnswerCount,0) AS AnswersPosted,
           COALESCE(badges.TotalBadges,0) AS BadgeCount,
           COALESCE(cmnt.CommentCount,0) AS CommentsMade,
           u.Reputation,
           u.CreationDate
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) pc ON pc.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) ac ON ac.OwnerUserId = u.Id
    LEFT JOIN UserBadgeStats badges ON badges.UserId = u.Id
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY UserId
    ) cmnt ON cmnt.UserId = u.Id
    WHERE u.Reputation > 500
      AND u.LastAccessDate > NOW() - INTERVAL '1 year'
)
SELECT
    rau.Id AS UserId,
    rau.DisplayName,
    rau.Reputation,
    uts.GoldBadges,
    uts.SilverBadges,
    uts.BronzeBadges,
    qas.QuestionId,
    qas.Title AS QuestionTitle,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    rcq.CloseReason,
    rcq.ClosedDate,
    rcq.ReopenCount,
    pls.DuplicateCount,
    usa.QuestionsPosted,
    usa.AnswersPosted,
    usa.BadgeCount,
    usa.CommentsMade
FROM RecentActiveUsers rau
LEFT JOIN UserBadgeStats uts ON uts.UserId = rau.Id
LEFT JOIN QuestionAnswerStats qas ON qas.QuestionId IN (
    SELECT Id FROM Posts
    WHERE OwnerUserId = rau.Id
      AND PostTypeId = 1
    ORDER BY Score DESC
    LIMIT 1
)
LEFT JOIN RecentClosedQuestions rcq ON rcq.PostId = qas.QuestionId
LEFT JOIN PostLinkDuplicates pls ON pls.PostId = qas.QuestionId
LEFT JOIN UserActivitySummary usa ON usa.Id = rau.Id
WHERE uts.GoldBadges > 0
  AND qas.AvgAnswerScore > 2
ORDER BY rau.Reputation DESC, qas.QuestionScore DESC
LIMIT 100;
