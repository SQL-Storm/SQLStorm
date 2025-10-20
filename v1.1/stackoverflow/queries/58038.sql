WITH GoldUsers AS (
    SELECT UserId, COUNT(*) AS GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
    HAVING COUNT(*) >= 5
), UserPosts AS (
    SELECT 
        u.Id AS UserId, 
        p.Id AS PostId, 
        p.Score, 
        p.ViewCount, 
        p.AnswerCount, 
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT string_agg(t.TagName, ', ')
         FROM (
           SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags)-2), '><')) AS tag
         ) taglist
         JOIN Tags t ON t.TagName = taglist.tag) AS Tags,
        (SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) AS AvgQuestionScore
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year'
), PostVotes AS (
    SELECT 
        p.UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN 1 ELSE 0 END) AS Bounties
    FROM UserPosts p
    JOIN Votes v ON v.PostId = p.PostId
    GROUP BY p.UserId
), CloseReasons AS (
    SELECT 
        ph.UserId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON crt.Id = CAST(ph.Comment AS INTEGER)
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY ph.UserId, crt.Name
)
SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    gu.GoldBadges,
    COUNT(up.PostId) AS TotalQuestions,
    AVG(up.Score) AS AvgPostScore,
    MAX(up.AvgQuestionScore) AS AvgAllQuestions,
    SUM(up.ViewCount) AS TotalViews,
    SUM(pv.Upvotes) AS TotalUpvotes,
    SUM(pv.Downvotes) AS TotalDownvotes,
    STRING_AGG(DISTINCT cr.CloseReason, ', ') AS CloseReasonsUsed,
    RANK() OVER (ORDER BY (u.Reputation * 0.3 + COUNT(up.PostId) * 0.2 + SUM(pv.Upvotes) * 0.5) DESC) AS UserRank
FROM Users u
JOIN GoldUsers gu ON gu.UserId = u.Id
JOIN UserPosts up ON up.UserId = u.Id
JOIN PostVotes pv ON pv.UserId = u.Id
LEFT JOIN CloseReasons cr ON cr.UserId = u.Id
GROUP BY u.Id, u.DisplayName, u.Reputation, gu.GoldBadges
HAVING COUNT(up.PostId) > 10
ORDER BY UserRank
LIMIT 100;