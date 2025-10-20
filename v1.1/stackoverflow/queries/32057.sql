SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS NetVotes,
    COUNT(CASE WHEN p_q.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p_a.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    COUNT(CASE WHEN b_g.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b_s.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b_b.Class = 3 THEN 1 END) AS BronzeBadges,
    COALESCE(COUNT(CASE WHEN c.UserId IS NOT NULL THEN 1 END), 0) AS CommentCount
FROM 
    Users u
LEFT JOIN 
    Votes v ON v.UserId = u.Id
LEFT JOIN
    Posts p_q ON p_q.OwnerUserId = u.Id AND p_q.PostTypeId = 1
LEFT JOIN
    Posts p_a ON p_a.OwnerUserId = u.Id AND p_a.PostTypeId = 2
LEFT JOIN
    Badges b_g ON b_g.UserId = u.Id AND b_g.Class = 1
LEFT JOIN
    Badges b_s ON b_s.UserId = u.Id AND b_s.Class = 2
LEFT JOIN
    Badges b_b ON b_b.UserId = u.Id AND b_b.Class = 3
LEFT JOIN
    Comments c ON c.UserId = u.Id
GROUP BY 
    u.Id,
    u.DisplayName
HAVING 
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) > 0
ORDER BY 
    NetVotes DESC, GoldBadges DESC, SilverBadges DESC, BronzeBadges DESC, AnswerCount DESC, QuestionCount DESC
LIMIT 100;