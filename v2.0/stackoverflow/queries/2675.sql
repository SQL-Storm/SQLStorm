WITH RECURSIVE RecursiveVotes AS (
    SELECT
        v.Id,
        v.PostId,
        v.VoteTypeId,
        v.UserId,
        v.CreationDate,
        v.BountyAmount,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.Tags,
        1 AS Depth
    FROM Votes v
    INNER JOIN Posts p ON p.Id = v.PostId
    WHERE v.VoteTypeId IN (2,3)

    UNION ALL

    SELECT
        v2.Id,
        v2.PostId,
        v2.VoteTypeId,
        v2.UserId,
        v2.CreationDate,
        v2.BountyAmount,
        p2.OwnerUserId,
        p2.PostTypeId,
        p2.Score,
        p2.ViewCount,
        p2.Tags,
        rv.Depth + 1
    FROM Votes v2
    INNER JOIN Posts p2 ON p2.Id = v2.PostId
    INNER JOIN RecursiveVotes rv ON rv.UserId = v2.UserId
    WHERE v2.CreationDate > rv.CreationDate
      AND rv.Depth < 3
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.TagBased = FALSE
    GROUP BY b.UserId, b.Class
),
UserRankAndActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        MAX(CASE WHEN p.PostTypeId IN (1,2) THEN p.Score END) AS MaxPostScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes
),
PostRelations AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p1.PostTypeId AS PostType_Source,
        p2.PostTypeId AS PostType_Target
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    INNER JOIN Posts p1 ON p1.Id = pl.PostId
    INNER JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    WHERE lt.Name IN ('Duplicate', 'Linked')
),
QuestionDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(p.AnswerCount,0) AS AnswerCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.Tags ORDER BY p.Score DESC, p.ViewCount DESC) AS TagTopRank,
        DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
CloseReasonDistribution AS (
    SELECT
        cht.Name AS CloseReason,
        COUNT(ph.Id) AS CloseCount
    FROM PostHistory ph
    LEFT JOIN PostHistoryTypes cht ON cht.Id = ph.PostHistoryTypeId
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY cht.Name
),
CTE_BadgedUsers AS (
    SELECT
        ubc.UserId,
        MAX(CASE WHEN ubc.Class = 1 THEN ubc.BadgeCount ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN ubc.Class = 2 THEN ubc.BadgeCount ELSE 0 END) AS SilverBadges,
        MAX(CASE WHEN ubc.Class = 3 THEN ubc.BadgeCount ELSE 0 END) AS BronzeBadges
    FROM UserBadgeCounts ubc
    GROUP BY ubc.UserId
)
SELECT
    u.DisplayName,
    u.Location,
    COALESCE(bu.GoldBadges,0) AS GoldBadges,
    COALESCE(bu.SilverBadges,0) AS SilverBadges,
    COALESCE(bu.BronzeBadges,0) AS BronzeBadges,
    u.Reputation,
    u.ReputationRank,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.MaxPostScore,
    u.TotalUpVotes,
    u.TotalDownVotes,
    (CAST(u.UpVotes AS DOUBLE PRECISION) / NULLIF(u.DownVotes,0)) AS UpDownRatio,
    q.Title AS TopQuestionTitle,
    q.Score AS TopQuestionScore,
    q.ViewCount AS TopQuestionViewCount,
    q.TagTopRank,
    pr.LinkTypeName,
    pr.PostId,
    pr.RelatedPostId,
    crd.CloseReason,
    crd.CloseCount,
    SUBSTR(u.DisplayName || ' - ' || COALESCE(u.Location,'Unknown'), 1, 40) AS DisplaySummary
FROM UserRankAndActivity u
LEFT JOIN CTE_BadgedUsers bu ON bu.UserId = u.UserId
LEFT JOIN LATERAL (
    SELECT
        p.Title,
        p.Score,
        p.ViewCount,
        p.TagTopRank
    FROM QuestionDetails p 
    WHERE p.OwnerUserId = u.UserId
    ORDER BY p.Score DESC
    LIMIT 1
) q ON TRUE
LEFT JOIN LATERAL (
    SELECT pr.LinkTypeName, pr.PostId, pr.RelatedPostId
    FROM PostRelations pr
    WHERE pr.PostType_Source = 1
      AND pr.PostId IN (
          SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.UserId AND p.PostTypeId = 1
      )
    ORDER BY pr.LinkTypeName, pr.PostId
    LIMIT 1
) pr ON TRUE
LEFT JOIN LATERAL (
    SELECT crd.CloseReason, crd.CloseCount
    FROM CloseReasonDistribution crd
    ORDER BY crd.CloseCount DESC
    LIMIT 1
) crd ON TRUE
WHERE u.QuestionsAsked > 5
  AND (u.Reputation > 1000 OR COALESCE(bu.GoldBadges,0) > 0)
  AND (u.Location IS NOT NULL AND u.Location <> '')
ORDER BY u.ReputationRank, bu.GoldBadges DESC, u.QuestionsAsked DESC
LIMIT 100;