SELECT
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
    COUNT(DISTINCT u.Id) AS DistinctUserCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount,
    AVG(u.Reputation) AS AvgUserReputation,
    COUNT(CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE NULL END) AS ClosedPostCount,
    COUNT(ph.Id) AS PostHistoryEventCount,
    COUNT(c.Id) AS CommentCount,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinkCount,
    AVG(EXTRACT(EPOCH FROM (p.CreationDate - u.CreationDate)) / 86400.0) AS AvgDaysBetweenUserCreationAndPost,
    SUM(CASE WHEN pht.Name = 'Edit Body' THEN 1 ELSE 0 END) AS EditBodyCount,
    SUM(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS PostClosedCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
    p.PostTypeId
FROM Posts AS p
LEFT JOIN Users AS u ON p.OwnerUserId = u.Id
LEFT JOIN Badges AS b ON u.Id = b.UserId
LEFT JOIN PostHistory AS ph ON p.Id = ph.PostId
LEFT JOIN PostHistoryTypes AS pht ON ph.PostHistoryTypeId = pht.Id
LEFT JOIN Comments AS c ON p.Id = c.PostId
LEFT JOIN PostLinks AS pl ON p.Id = pl.PostId
LEFT JOIN Votes AS v ON p.Id = v.PostId
WHERE p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR)
GROUP BY
    p.PostTypeId,
    p.CreationDate,
    u.CreationDate,
    u.Id,
    u.Reputation,
    b.Class,
    ph.Id,
    c.Id,
    pl.LinkTypeId,
    pht.Name,
    v.VoteTypeId
ORDER BY
    p.PostTypeId;