-- {"query": "1378.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1819} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        1 AS Depth,
        ARRAY[t.TagName] AS Ancestry
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT 
        child.Id,
        child.TagName,
        child.Count,
        child.WikiPostId,
        parent.Depth + 1,
        parent.Ancestry || child.TagName
    FROM Tags child
    JOIN RecursiveTagHierarchy parent ON child.WikiPostId = parent.WikiPostId
    WHERE NOT child.TagName = ANY(parent.Ancestry) AND child.IsRequired = 1
), 
AnswerRanks AS (
    SELECT 
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS RankByScore,
        LAG(a.UserId) OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS PrevAnswerUserId
    FROM Posts a
    WHERE a.PostTypeId = 2 -- Answers
),
QuestionSummary AS (
    SELECT
        q.Id,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.AcceptedAnswerId,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS TotalComments,
        vir.VoteCountUp,
        react.ScoreReactions,
        COALESCE(phc.LastClosedDate, q.ClosedDate) AS LastClosedDate,
        q.ClosedDate IS NOT NULL AS IsClosed,
        ROW_NUMBER() OVER(ORDER BY q.Score DESC NULLS LAST) AS QuestionRank
    FROM Posts q
    LEFT JOIN (
        SELECT PostId, COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS VoteCountUp
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY PostId
    ) vir ON vir.PostId = q.Id
    LEFT JOIN (
        SELECT 
            ph.PostId, 
            SUM(COALESCE(LENGTH(ph.Text) - LENGTH(REPLACE(ph.Text, ':)', '')),0)) - 
            SUM(COALESCE(LENGTH(ph.Text) - LENGTH(REPLACE(ph.Text, ':(', '')),0)) AS ScoreReactions
        FROM PostHistory ph
        GROUP BY ph.PostId
    ) react ON react.PostId = q.Id
    LEFT JOIN (
        SELECT PostId, MAX(CreationDate) AS LastClosedDate
        FROM PostHistory ph2
        WHERE ph2.PostHistoryTypeId = 10 -- Post Closed events
        GROUP BY PostId
    ) phc ON phc.PostId = q.Id
    WHERE q.PostTypeId = 1
), 
UserReputationStats AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1,2)
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(b.Id) > 5
),
LinkAggregates AS (
    SELECT 
        l.PostId,
        l.LinkTypeId,
        COUNT(*) AS LinkCount,
        MAX(l.CreationDate) AS LastLinkDate
    FROM PostLinks l
    GROUP BY l.PostId, l.LinkTypeId
),
PostsWithRanks AS (
    SELECT
        ps.Id,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.CreationDate,
        CASE WHEN ps.PostTypeId = 1 THEN rs.RankByScore ELSE NULL END AS AnswerRank,
        u.FavCount,
        u.RepAdjustedRank,
        phatid.LastHistoryType,
        phatid.RecentHistoryDate
    FROM Posts ps
    LEFT JOIN (
        SELECT 
            h.PostId, 
            max(h.PostHistoryTypeId) AS LastHistoryType,
            max(h.CreationDate) AS RecentHistoryDate
        FROM PostHistory h
        GROUP BY h.PostId
    ) phatid ON phatid.PostId = ps.Id
    LEFT JOIN (
        SELECT
            OwnerUserId,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnswersCount
        FROM Posts
        GROUP BY OwnerUserId
    ) asCount ON asCount.OwnerUserId = ps.OwnerUserId
    LEFT JOIN (
        SELECT 
            UserId, SUM(COALESCE(FavoriteCount, 0)) AS FavCount,
            RANK() OVER (ORDER BY SUM(COALESCE(FavoriteCount, 0)) DESC) AS RepAdjustedRank
        FROM Posts p2
        WHERE p2.PostTypeId = 1
        GROUP BY UserId
    ) u ON u.UserId = ps.OwnerUserId
    LEFT JOIN AnswerRanks rs ON rs.Id = ps.Id
    WHERE ps.PostTypeId IN (1,2)
)
SELECT
    qs.Id AS QuestionId,
    qs.Title,
    qs.CreationDate,
    qs.Score,
    qs.ViewCount,
    qs.Tags,
    qs.AcceptedAnswerId,
    COALESCE(ur.GoldBadges,0) AS GoldBadges,
    COALESCE(ur.SilverBadges,0) AS SilverBadges,
    COALESCE(ur.BronzeBadges,0) AS BronzeBadges,
    ur.DisplayName AS QuestionOwnerDisplay,
    qs.TotalComments,
    lyr.LinkCount FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateLinksCount,
    ROUND(NULLIF(avgAnsScores.avg_answer_score, 0),2) AS AvgAnswerScore,
    CASE 
        WHEN qs.IsClosed THEN 'Closed'
        ELSE 'Open'
    END AS QuestionStatus,
    STRING_AGG(DISTINCT COALESCE(u.Location,'Unknown'), ', ') FILTER (WHERE u.Id IS NOT NULL) AS AnswererLocations,
    MAX(a.CreationDate) AS LatestAnswerDate,
    COALESCE(wikipedia.BigImpactCount,0) AS BigImpactAnsweredTimes
FROM QuestionSummary qs
LEFT JOIN LinkAggregates lyr ON lyr.PostId = qs.Id
LEFT JOIN LinkTypes lt ON lt.Id = lyr.LinkTypeId
LEFT JOIN UserReputationStats ur ON ur.Id = qs.OwnerUserId
LEFT JOIN (
    SELECT 
        p.ParentId,
        AVG(p.Score) AS avg_answer_score,
        COUNT(*) FILTER (WHERE p.Score > 10) AS BigImpactCount
    FROM Posts p
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
) avgAnsScores ON avgAnsScores.ParentId = qs.Id
LEFT JOIN Posts a ON a.ParentId = qs.Id AND a.PostTypeId = 2
LEFT JOIN Users u ON u.Id = a.OwnerUserId
LEFT JOIN PostsWithRanks pwrr ON pwrr.Id = a.Id
LEFT JOIN (
    SELECT
        p.Id,
        SUM(CASE WHEN ph.PostHistoryTypeId = 50 THEN 1 ELSE 0 END) AS CommunityBumps
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    GROUP BY p.Id
) wikipedia ON wikipedia.Id = qs.Id
GROUP BY
    qs.Id,
    qs.Title,
    qs.CreationDate,
    qs.Score,
    qs.ViewCount,
    qs.Tags,
    qs.AcceptedAnswerId,
    ur.GoldBadges,
    ur.SilverBadges,
    ur.BronzeBadges,
    ur.DisplayName,
    qs.TotalComments,
    lyr.LinkCount,
    lt.Name,
    avgAnsScores.avg_answer_score,
    avgAnsScores.BigImpactCount,
    qs.IsClosed,
    wikipedia.BigImpactCount
HAVING AVG(COALESCE(a.Score,0)) IS NOT NULL
ORDER BY qs.Score DESC, LatestAnswerDate DESC
LIMIT 100;
