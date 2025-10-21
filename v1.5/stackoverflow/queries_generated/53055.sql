-- {"query": "53055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 825} 

WITH PopularTags AS (
    SELECT t.TagName, t.Count AS TagUsage,
           ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.Count > 10000
),
TopQuestions AS (
    SELECT p.Id AS QuestionId, p.Title, p.ViewCount, p.Score AS QuestionScore,
           pt.TagName,
           COUNT(DISTINCT a.Id) AS AnswerCount,
           SUM(a.Score) AS TotalAnswerScore,
           MAX(a.Score) AS MaxAnswerScore,
           AVG(c.Score) AS AvgCommentScore,
           COUNT(DISTINCT v.Id) AS TotalVotes,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM Posts p
    JOIN PopularTags pt ON p.Tags LIKE '%' || pt.TagName || '%'
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Comments c ON c.PostId IN (p.Id, a.Id)
    LEFT JOIN Votes v ON v.PostId IN (p.Id, a.Id)
    WHERE p.PostTypeId = 1 AND p.CreationDate >= '2015-01-01' AND p.Score > 50
    GROUP BY p.Id, p.Title, p.ViewCount, p.Score, pt.TagName
    HAVING COUNT(DISTINCT a.Id) >= 5 AND SUM(a.Score) > 100
),
UserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
           COUNT(DISTINCT ph.Id) AS EditCount,
           SUM(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN 1 ELSE 0 END) AS SignificantEdits,
           COUNT(DISTINCT b.Id) AS BadgeCount,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           COUNT(DISTINCT pl.Id) AS LinkCount
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    JOIN TopQuestions tq ON tq.QuestionId = p.Id OR p.ParentId = tq.QuestionId
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT ph.Id) > 10
),
RankedUsers AS (
    SELECT ua.*,
           RANK() OVER (PARTITION BY ua.UserId ORDER BY ua.Reputation DESC) AS UserRank,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ua.EditCount) OVER () AS MedianEdits
    FROM UserActivity ua
)
SELECT ru.DisplayName, ru.Reputation, ru.EditCount, ru.SignificantEdits, ru.BadgeCount, ru.GoldBadges,
       ru.LinkCount, ru.UserRank, ru.MedianEdits,
       tq.Title, tq.ViewCount, tq.QuestionScore, tq.TagName, tq.AnswerCount, tq.TotalAnswerScore,
       tq.MaxAnswerScore, tq.AvgCommentScore, tq.TotalVotes, tq.Upvotes, tq.Downvotes
FROM RankedUsers ru
JOIN Posts p ON p.OwnerUserId = ru.UserId
JOIN TopQuestions tq ON tq.QuestionId = p.Id OR p.ParentId = tq.QuestionId
WHERE ru.UserRank <= 10
ORDER BY ru.Reputation DESC, tq.ViewCount DESC
LIMIT 1000;
