WITH UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation
),
PostSummaries AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ContentLicense,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostCategory,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM Posts p
),
EditedPosts AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(ph.Comment, ' | ') AS EditComments,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 6, 10, 12, 13, 14, 15) THEN 1 END) AS EditCount,
        COUNT(DISTINCT ph.UserId) AS EditorCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 6, 10, 12, 13, 14, 15)
    GROUP BY ph.PostId
),
LinkStats AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT CASE WHEN l.LinkTypeId = 1 THEN l.RelatedPostId END) AS LinkedCount,
        COUNT(DISTINCT CASE WHEN l.LinkTypeId = 3 THEN l.RelatedPostId END) AS DuplicatedCount
    FROM Posts p
    LEFT JOIN PostLinks l ON p.Id = l.PostId
    GROUP BY p.Id
),
VoteSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN v.VoteTypeId = 1 AND p.PostTypeId = 1 THEN 1 END) AS AcceptedVotes
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.PostTypeId
),
AggregateData AS (
    SELECT
        ps.PostId,
        ps.PostTypeId,
        ps.Title,
        ps.Tags,
        ps.CreationDate,
        ps.OwnerUserId,
        ur.Reputation,
        ur.GoldBadges,
        ur.SilverBadges,
        ur.BronzeBadges,
        es.LastEditDate,
        es.EditComments,
        es.EditCount,
        es.EditorCount,
        ls.LinkedCount,
        ls.DuplicatedCount,
        vs.UpVotes,
        vs.DownVotes,
        vs.AcceptedVotes,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.FavoriteCount,
        ps.LastActivityDate,
        ps.ContentLicense,
        CASE WHEN ps.PostTypeId = 1 AND ps.Tags IS NOT NULL THEN NULL ELSE NULL END AS TagPlaceholder,
        ps.PostCategory
    FROM PostSummaries ps
    LEFT JOIN UserReputation ur ON ps.OwnerUserId = ur.UserId
    LEFT JOIN EditedPosts es ON ps.PostId = es.PostId
    LEFT JOIN LinkStats ls ON ps.PostId = ls.PostId
    LEFT JOIN VoteSummary vs ON ps.PostId = vs.PostId
)
SELECT
    ad.*,
    COUNT(*) OVER () AS TotalPosts,
    SUM(CASE WHEN ad.PostCategory = 'Question' THEN 1 ELSE 0 END) OVER () AS TotalQuestions,
    SUM(CASE WHEN ad.PostCategory = 'Answer' THEN 1 ELSE 0 END) OVER () AS TotalAnswers
FROM AggregateData ad
WHERE
    (ad.Reputation IS NULL OR ad.Reputation >= 0)
    AND (ad.LastEditDate IS NULL OR ad.LastEditDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30' DAY))
    AND (ad.LinkedCount IS NULL OR ad.LinkedCount >= 0)
    AND (ad.DuplicatedCount IS NULL OR ad.DuplicatedCount >= 0)
    AND ((COALESCE(ad.UpVotes,0) + COALESCE(ad.DownVotes,0)) > 0)
ORDER BY
    ad.LastActivityDate DESC
LIMIT 100;