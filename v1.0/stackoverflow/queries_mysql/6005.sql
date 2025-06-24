
SELECT 
    u.DisplayName AS UserName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    GROUP_CONCAT(DISTINCT t.TagName) AS TagsUsed,
    MAX(ph.CreationDate) AS LastPostDate
FROM 
    Users u
LEFT JOIN 
    Posts p ON u.Id = p.OwnerUserId
LEFT JOIN 
    Badges b ON u.Id = b.UserId
LEFT JOIN 
    (SELECT 
        p.Id AS post_id, 
        unnest(string_to_array(p.Tags, '><')) AS TagName
     FROM 
        Posts p
     WHERE 
        p.PostTypeId = 1) t ON p.Id = t.post_id
LEFT JOIN 
    PostHistory ph ON p.Id = ph.PostId
WHERE 
    u.CreationDate > DATE_SUB(CURDATE(), INTERVAL 1 YEAR)
GROUP BY 
    u.Id, u.DisplayName, u.Reputation
HAVING 
    COUNT(DISTINCT p.Id) > 10
ORDER BY 
    u.Reputation DESC;
