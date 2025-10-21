SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetVotes,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2) AS AnswerCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
    COALESCE((SELECT COUNT(*) FROM Comments c WHERE c.UserId = u.Id), 0) AS CommentCount
FROM 
    Users u
LEFT JOIN 
    Votes v ON v.UserId = u.Id
GROUP BY 
    u.Id, u.DisplayName
HAVING 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) > 0
ORDER BY 
    NetVotes DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC, AnswerCount DESC, QuestionCount DESC
LIMIT 100;