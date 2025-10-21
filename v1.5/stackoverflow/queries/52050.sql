-- {"query": "52050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2165, "output_tokens": 366} 
SELECT
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
    (SELECT SUM(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS TotalScore,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
    (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id) AS VotesGiven,
    (SELECT COUNT(*) FROM Votes v JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = u.Id AND v.VoteTypeId IN (2,3)) AS VotesReceived,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id) AS BadgeCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank
FROM Users u
WHERE u.Reputation > 1000
ORDER BY u.Reputation DESC
LIMIT 50;