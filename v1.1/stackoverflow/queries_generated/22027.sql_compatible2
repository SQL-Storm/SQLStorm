WITH UserStats AS (
    SELECT u.Id AS UserId,
           u.Reputation,
           u.DisplayName,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS NumQuestions,
           COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS NumAnswers,
           COALESCE(SUM(p.Score), 0) AS TotalScore,
           AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews,
           STRING_AGG(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL THEN SUBSTRING(p.Tags FROM 2 FOR (LENGTH(p.Tags) - 2)) END, '; ') AS QuestionTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.Reputation, u.DisplayName
    HAVING COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
),
BadgeCounts AS (
    SELECT b.UserId,
           COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
           COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
           COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Badges b
    WHERE b.Date >= DATE '2020-01-01'
    GROUP BY b.UserId
),
EditHistory AS (
    SELECT ph.UserId,
           COUNT(*) AS NumEdits,
           MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY ph.UserId
),
VoteMetrics AS (
    SELECT v.UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes
    FROM Votes v
    GROUP BY v.UserId
)
SELECT us.UserId,
       us.Reputation,
       us.DisplayName,
       us.NumQuestions,
       us.NumAnswers,
       us.TotalScore,
       us.AvgQuestionViews,
       us.QuestionTags,
       COALESCE(bc.GoldBadges, 0) AS GoldBadges,
       COALESCE(bc.SilverBadges, 0) AS SilverBadges,
       COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
       COALESCE(eh.NumEdits, 0) AS NumEdits,
       eh.LastEditDate,
       COALESCE(vm.NetVotes, 0) AS NetVotes,
       (us.Reputation * 1.0 / NULLIF(us.NumQuestions + us.NumAnswers, 0)) *
       CASE WHEN POSITION('sql' IN LOWER(COALESCE(us.QuestionTags, ''))) > 0 THEN 1.5 ELSE 1.0 END AS CustomScore,
       RANK() OVER (ORDER BY (us.Reputation * 1.0 / NULLIF(us.NumQuestions + us.NumAnswers, 0)) *
       CASE WHEN POSITION('sql' IN LOWER(COALESCE(us.QuestionTags, ''))) > 0 THEN 1.5 ELSE 1.0 END DESC) AS Rank
FROM UserStats us
LEFT JOIN BadgeCounts bc ON us.UserId = bc.UserId
LEFT JOIN EditHistory eh ON us.UserId = eh.UserId
LEFT JOIN VoteMetrics vm ON us.UserId = vm.UserId
WHERE EXISTS (
    SELECT 1 FROM Comments c
    WHERE c.UserId = us.UserId
      AND LENGTH(c.Text) > 50
      AND c.Score > 5
)
GROUP BY
    us.UserId,
    us.Reputation,
    us.DisplayName,
    us.NumQuestions,
    us.NumAnswers,
    us.TotalScore,
    us.AvgQuestionViews,
    us.QuestionTags,
    bc.GoldBadges,
    bc.SilverBadges,
    bc.BronzeBadges,
    eh.NumEdits,
    eh.LastEditDate,
    vm.NetVotes,
    (us.Reputation * 1.0 / NULLIF(us.NumQuestions + us.NumAnswers, 0)) *
    CASE WHEN POSITION('sql' IN LOWER(COALESCE(us.QuestionTags, ''))) > 0 THEN 1.5 ELSE 1.0 END
ORDER BY Rank
LIMIT 10;