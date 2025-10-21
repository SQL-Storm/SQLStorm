SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    AVG(p.Score) AS AverageQuestionScore,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    (SELECT MAX(CreationDate) FROM Posts WHERE OwnerUserId = u.Id) AS MostRecentPostDate
FROM
    Users u
JOIN
    Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
LEFT JOIN
    Votes v ON v.PostId = p.Id
LEFT JOIN
    Badges b ON b.UserId = u.Id
WHERE
    u.Reputation > 1000
    AND p.CreationDate > DATE '2018-01-01'
GROUP BY
    u.Id, u.DisplayName
HAVING
    COUNT(DISTINCT p.Id) > 10
ORDER BY
    AverageQuestionScore DESC, VoteCount DESC
LIMIT 100;