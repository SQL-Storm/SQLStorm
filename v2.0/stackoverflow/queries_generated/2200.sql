-- {"query": "2200.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1453} 

WITH RecentTopQuestions AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate > NOW() - INTERVAL '180 days'
      AND p.Score IS NOT NULL
),
UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
UserActivityWindow AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsCount,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS AnswersCount,
        COUNT(DISTINCT c.Id) AS CommentsCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1 OR p.PostTypeId = 2) OVER (PARTITION BY u.Id) AS AvgPostScore,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS UserRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
DuplicatesAndLinks AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        EXISTS (
            SELECT 1 FROM PostHistory ph 
            WHERE ph.PostId = pl.PostId AND ph.PostHistoryTypeId IN (10, 12) -- Closed or Deleted via history
        ) AS WasPostClosedOrDeleted
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
QuestionWithAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) AS QuestionUpvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) AS QuestionDownvotes,
        COALESCE((
            SELECT AVG(a2.Score) FROM Posts a2 WHERE a2.ParentId = q.Id AND a2.PostTypeId = 2
        ), 0) AS AvgAnswerScore,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS TotalComments
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
UserRecentEdits AS (
    SELECT
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        MAX(ph.CreationDate) AS LastEditDate,
        COUNT(*) AS EditsCount
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
      AND ph.CreationDate > NOW() - INTERVAL '90 days'
    GROUP BY ph.UserId, ph.PostId, ph.PostHistoryTypeId
),
FilteredTopUsers AS (
    SELECT uaw.Id, uaw.DisplayName, uaw.Reputation, uaw.QuestionsCount, uaw.AnswersCount, uaw.CommentsCount, uaw.AvgPostScore,
           ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.TotalBadges, uaw.UserRank
    FROM UserActivityWindow uaw
    INNER JOIN UserBadgeSummary ubs ON ubs.UserId = uaw.Id
    WHERE uaw.Reputation > 1000
      AND ubs.GoldBadges >= 3
      AND uaw.QuestionsCount > 5
      AND uaw.AnswersCount > 10
)
SELECT
    ftu.DisplayName,
    ftu.Reputation,
    ftu.QuestionsCount,
    ftu.AnswersCount,
    ftu.CommentsCount,
    ftu.AvgPostScore,
    ftu.GoldBadges,
    ftu.SilverBadges,
    ftu.BronzeBadges,
    qas.Title AS TopQuestionTitle,
    qas.QuestionScore,
    qas.ViewCount,
    qas.AnswerCount,
    qas.CommentCount,
    qas.AcceptedAnswerId,
    qas.AcceptedAnswerScore,
    qas.AvgAnswerScore,
    dup.LinkTypeName,
    dup.WasPostClosedOrDeleted,
    COALESCE(ure.LastEditDate, '1970-01-01') AS LastEditDate,
    ure.EditsCount,
    CASE 
      WHEN ftu.Reputation IS NULL THEN 'No reputation'
      WHEN ftu.Reputation < 2000 THEN 'Newbie'
      WHEN ftu.Reputation < 10000 THEN 'Intermediate'
      ELSE 'Expert' END AS ReputationCategory,
    CONCAT('User_', ftu.Id::text, '_Rank_', ftu.UserRank::text) AS UserRankLabel
FROM FilteredTopUsers ftu
LEFT JOIN RecentTopQuestions rtq ON rtq.OwnerUserId = ftu.Id AND rtq.rn = 1
LEFT JOIN QuestionWithAnswerStats qas ON qas.QuestionId = rtq.Id
LEFT JOIN DuplicatesAndLinks dup ON dup.PostId = qas.QuestionId
LEFT JOIN UserRecentEdits ure ON ure.UserId = ftu.Id AND ure.PostId = qas.QuestionId
WHERE qas.Score > COALESCE(
    (
        SELECT AVG(Score) FROM Posts p WHERE p.PostTypeId = 1
    ), 0
)
ORDER BY ftu.Reputation DESC, qas.QuestionScore DESC
LIMIT 25
