-- {"query": "2992.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1158}
WITH RecursiveUserBadges AS (
    SELECT 
       u.Id AS UserId, 
       u.DisplayName, 
       b.Name AS BadgeName, 
       b.Class AS BadgeClass,
       ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC, b.Class) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Date >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
),
TopBadgesPerUser AS (
    SELECT UserId, DisplayName, BadgeName, BadgeClass, BadgeRank
    FROM RecursiveUserBadges
    WHERE BadgeRank <= 3
),
RecentQuestionStats AS (
    SELECT 
       p.Id AS QuestionId, 
       p.Title, 
       p.OwnerUserId,
       p.CreationDate, 
       p.Score,
       p.ViewCount,
       COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate) AS RecentCommentCount,
       (SELECT AVG(v2.Score) 
        FROM Posts v2 
        WHERE v2.ParentId = p.Id AND v2.CreationDate BETWEEN p.CreationDate AND (p.CreationDate + INTERVAL '30 days')) AS AvgAnswerScore30d,
       p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.CreationDate > CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months'
),
AnswerWindowStats AS (
    SELECT 
       a.Id AS AnswerId,
       a.ParentId AS QuestionId,
       a.OwnerUserId,
       a.CreationDate,
       a.Score,
       COUNT(*) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AnswerSequence,
       MAX(a.Score) OVER (PARTITION BY a.ParentId) AS MaxAnswerScoreForQuestion
    FROM Posts a
    WHERE a.PostTypeId = 2
),
PostLinkAggregates AS (
    SELECT 
       pl.PostId,
       SUM(CASE WHEN lt.Name = 'Duplicate' THEN 1 ELSE 0 END) AS DuplicateLinksCount,
       SUM(CASE WHEN lt.Name = 'Linked' THEN 1 ELSE 0 END) AS LinkedPostsCount,
       COUNT(pl.RelatedPostId) AS TotalRelatedPosts
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
ClosedQuestionsWithReason AS (
    SELECT DISTINCT
       ph.PostId,
       crt.Name AS CloseReason,
       ph.CreationDate AS ClosedAt
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
)
SELECT 
    q.QuestionId,
    q.Title,
    u.DisplayName AS QuestionOwner,
    u.Reputation,
    q.Score AS QuestionScore,
    q.ViewCount,
    COALESCE(ab.BadgeName, 'No Recent Badge') AS TopUserBadge,
    ab.BadgeClass,
    q.RecentCommentCount,
    COALESCE(q.AvgAnswerScore30d, 0) AS AvgAnswerScoreLast30Days,
    ans.AnswerCount,
    ans.MaxAnswerScoreForQuestion,
    pq.DuplicateLinksCount,
    pq.LinkedPostsCount,
    pq.TotalRelatedPosts,
    cqt.CloseReason,
    cqt.ClosedAt,
    STRING_AGG(DISTINCT tg.TagName, ', ') FILTER (WHERE tg.TagName IS NOT NULL) AS Tags,
    STRING_AGG(DISTINCT COALESCE(pht.Name, 'Unknown'), '; ') AS PostHistoryEventSummary
FROM RecentQuestionStats q
INNER JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN (
    SELECT 
       UserId,
       BadgeName,
       BadgeClass,
       BadgeRank
    FROM TopBadgesPerUser
) ab ON ab.UserId = u.Id AND ab.BadgeRank = 1
LEFT JOIN (
    SELECT 
       aw.QuestionId,
       COUNT(aw.AnswerId) AS AnswerCount,
       MAX(aw.MaxAnswerScoreForQuestion) AS MaxAnswerScoreForQuestion
    FROM AnswerWindowStats aw
    GROUP BY aw.QuestionId
) ans ON ans.QuestionId = q.QuestionId
LEFT JOIN PostLinkAggregates pq ON pq.PostId = q.QuestionId
LEFT JOIN ClosedQuestionsWithReason cqt ON cqt.PostId = q.QuestionId
LEFT JOIN Tags tg ON POSITION(CONCAT('<', tg.TagName, '>') IN COALESCE(q.Tags, '')) > 0
LEFT JOIN PostHistory ph ON ph.PostId = q.QuestionId AND ph.CreationDate > q.CreationDate - INTERVAL '1 year'
LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
GROUP BY 
    q.QuestionId, q.Title, u.DisplayName, u.Reputation, q.Score, q.ViewCount, 
    ab.BadgeName, ab.BadgeClass, q.RecentCommentCount, q.AvgAnswerScore30d, 
    ans.AnswerCount, ans.MaxAnswerScoreForQuestion, pq.DuplicateLinksCount, pq.LinkedPostsCount, pq.TotalRelatedPosts, 
    cqt.CloseReason, cqt.ClosedAt, q.CreationDate, -- ph.CreationDate and pht.Name removed from ORDER BY/aggregates to avoid DISTINCT/ORDER BY conflict
    q.Tags
ORDER BY q.Score DESC NULLS LAST, q.ViewCount DESC NULLS LAST, q.CreationDate DESC
LIMIT 50;