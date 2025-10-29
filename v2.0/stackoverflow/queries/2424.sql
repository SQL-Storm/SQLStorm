-- {"query": "2424.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1357}
WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, 0 AS Level
    FROM Tags t
    WHERE t.IsRequired = TRUE
    UNION ALL
    SELECT t2.Id, t2.TagName, t2.Count, t2.IsModeratorOnly, t2.IsRequired, r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id = r.Id + 1
), LatestUserActivity AS (
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY MAX(p.LastActivityDate) DESC) AS ActivityRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
), PostScoreWindow AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId,
        p.Score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) AS PostRankInType,
        CASE 
            WHEN p.Tags IS NOT NULL THEN array_length(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'), 1)
            ELSE 0 
        END AS TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
), AcceptedAnswerInfo AS (
    SELECT q.Id AS QuestionId, a.Id AS AcceptedAnswerId, a.Score AS AcceptedAnswerScore,
        u.DisplayName AS AcceptedAnswerOwner, u.Reputation AS AcceptedAnswerOwnerRep
    FROM Posts q
    LEFT JOIN Posts a ON q.AcceptedAnswerId = a.Id
    LEFT JOIN Users u ON a.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1 AND q.AcceptedAnswerId IS NOT NULL
), CloseDetail AS (
    SELECT ph.PostId, crt.Name AS CloseReason, ph.CreationDate AS CloseDate
    FROM PostHistory ph
    INNER JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INTEGER) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
), UserBadgeSummary AS (
    SELECT b.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        BOOL_OR(b.TagBased) AS HasTagBasedBadge
    FROM Badges b
    GROUP BY b.UserId
)
SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    l.LastPostActivity AS LatestPostActivity,
    l.LastCommentDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges,
    us.HasTagBasedBadge,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.FavoriteCount,
    psw.TagCount,
    a.AcceptedAnswerId,
    a.AcceptedAnswerScore,
    a.AcceptedAnswerOwner,
    a.AcceptedAnswerOwnerRep,
    cd.CloseReason,
    cd.CloseDate,
    CASE WHEN p.Score > 0 AND p.ViewCount > 1000 THEN 'Hot'
         WHEN p.Score < 0 THEN 'Controversial'
         ELSE 'Normal' END AS PostStatus,
    string_agg(DISTINCT pht.Name, ', ') AS EditHistories,
    concat('[', string_agg(DISTINCT t.TagName, ', '), ']') AS TagsArray,
    CASE WHEN us.GoldBadges > 0 AND us.TotalBadges > 10 THEN 'Veteran Badge Collector'
         WHEN us.TotalBadges > 5 THEN 'Intermediate Badge Collector'
         ELSE 'Newbie Badge Collector' END AS BadgeTier
FROM Users u
INNER JOIN LatestUserActivity l ON u.Id = l.UserId AND l.ActivityRank = 1
LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
LEFT JOIN AcceptedAnswerInfo a ON a.QuestionId = p.Id AND p.PostTypeId = 1
LEFT JOIN CloseDetail cd ON cd.PostId = p.Id
LEFT JOIN PostScoreWindow psw ON psw.Id = p.Id
LEFT JOIN UserBadgeSummary us ON us.UserId = u.Id
LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)
LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
LEFT JOIN LATERAL (
    SELECT t.TagName
    FROM Tags t
    WHERE p.Tags IS NOT NULL
      AND t.TagName = ANY(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><'))
) t ON TRUE
WHERE u.Reputation > (
    SELECT AVG(Reputation) FROM Users
) AND 
(
    (p.Score IS NOT NULL AND p.Score > 5) 
    OR EXISTS (
        SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days')
    )
)
GROUP BY u.Id, u.DisplayName, u.Reputation, u.Location, l.LastPostActivity, l.LastCommentDate, u.Views, u.UpVotes, u.DownVotes, us.TotalBadges, us.GoldBadges, us.SilverBadges, us.BronzeBadges, us.HasTagBasedBadge, p.Id, p.PostTypeId, p.Title, p.Score, p.ViewCount, p.FavoriteCount, psw.TagCount, a.AcceptedAnswerId, a.AcceptedAnswerScore, a.AcceptedAnswerOwner, a.AcceptedAnswerOwnerRep, cd.CloseReason, cd.CloseDate
ORDER BY u.Reputation DESC, p.Score DESC
LIMIT 100;