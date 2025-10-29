WITH RECURSIVE RecursiveTaggedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        (SELECT ARRAY_AGG(tag) FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2), '><')) AS tag) AS TagArray,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        1 AS Depth
    FROM Posts p
    WHERE p.PostTypeId = 1

    UNION ALL

    SELECT 
        childp.Id,
        childp.PostTypeId,
        childp.Title,
        childp.Tags,
        parent.TagArray,
        childp.CreationDate,
        childp.Score,
        childp.ViewCount,
        childp.OwnerUserId,
        parent.Depth + 1
    FROM Posts childp
    INNER JOIN RecursiveTaggedPosts parent ON childp.ParentId = parent.Id
    WHERE childp.PostTypeId = 2
),
BadgeCounts AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostScores AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 WHEN vt.Name = 'DownMod' THEN -1 ELSE 0 END) AS VoteScore,
        COUNT(DISTINCT v.UserId) AS UniqueVoters
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
LatestComments AS (
    SELECT 
        c.PostId,
        c.Id AS CommentId,
        c.Text AS CommentText,
        c.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.CreationDate DESC) AS rn
    FROM Comments c
),
PostHistoryEdits AS (
    SELECT 
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,7,8,9) THEN 1 END) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        MIN(ph.CreationDate) AS FirstEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
DuplicateLinks AS (
    SELECT DISTINCT
        pl.PostId AS DuplicatePostId,
        pl.RelatedPostId AS OriginalPostId
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE lt.Name = 'Duplicate'
),
UserActivityRanked AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        bc.TotalBadges,
        RANK() OVER (ORDER BY u.Reputation DESC, bc.TotalBadges DESC) as ReputationRank,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionsAsked,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswersGiven,
        COALESCE(SUM(ps.VoteScore), 0) AS TotalPostScore
    FROM Users u
    LEFT JOIN BadgeCounts bc ON bc.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN PostScores ps ON ps.PostId = p.Id
    GROUP BY 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes,
        bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges, bc.TotalBadges
)
SELECT 
    rp.Id AS PostId,
    rp.PostTypeId,
    rp.Title,
    ARRAY_TO_STRING(rp.TagArray, ', ') AS Tags,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    us.DisplayName AS PostOwner,
    us.Reputation AS OwnerReputation,
    us.ReputationRank,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    ph.EditCount,
    ph.FirstEditDate,
    ph.LastEditDate,
    ps.VoteScore,
    ps.UniqueVoters,
    dc.OriginalPostId AS DuplicateOfPostId,
    lc.CommentId AS LatestCommentId,
    lc.CommentText AS LatestCommentText,
    CASE 
        WHEN rp.Score > 100 AND ps.VoteScore > 150 THEN 'Hot'
        WHEN rp.Score BETWEEN 50 AND 100 THEN 'Warm'
        WHEN rp.Score BETWEEN 1 AND 49 THEN 'Cold'
        ELSE 'Cold'
    END AS PopularityLabel,
    (SELECT STRING_AGG(DISTINCT UPPER(TRIM(t.TagName)), ', ')
     FROM UNNEST(rp.TagArray) AS tagstr
     JOIN Tags t ON t.TagName = tagstr
     WHERE t.Count > 1000
    ) AS PopularTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = rp.Id AND c.CreationDate > rp.CreationDate + INTERVAL '1 day') AS CommentsAfterFirstDay,
    (SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = rp.Id AND a.PostTypeId = 2) AS AverageAnswerScore,
    CASE WHEN us.GoldBadges >= 3 AND us.Reputation > 10000 THEN 'Top Contributor' ELSE 'Regular' END AS OwnerStatus
FROM RecursiveTaggedPosts rp
LEFT JOIN UserActivityRanked us ON us.Id = rp.OwnerUserId
LEFT JOIN PostHistoryEdits ph ON ph.PostId = rp.Id
LEFT JOIN PostScores ps ON ps.PostId = rp.Id
LEFT JOIN DuplicateLinks dc ON dc.DuplicatePostId = rp.Id
LEFT JOIN LatestComments lc ON lc.PostId = rp.Id AND lc.rn = 1
WHERE rp.Depth = 1
  AND rp.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years'
  AND (
    rp.Tags LIKE '%<sql>%'
    OR rp.Tags LIKE '%<performance>%'
    OR rp.Tags LIKE '%<optimization>%'
  )

UNION

SELECT
    p.Id AS PostId,
    p.PostTypeId,
    COALESCE(p.Title, '(no title)') AS Title,
    NULL AS Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName AS PostOwner,
    u.Reputation,
    NULL AS ReputationRank,
    0 AS GoldBadges,
    0 AS SilverBadges,
    0 AS BronzeBadges,
    0 AS EditCount,
    NULL AS FirstEditDate,
    NULL AS LastEditDate,
    COALESCE(ps.VoteScore, 0) AS VoteScore,
    COALESCE(ps.UniqueVoters, 0) AS UniqueVoters,
    NULL AS DuplicateOfPostId,
    NULL AS LatestCommentId,
    NULL AS LatestCommentText,
    'Cold' AS PopularityLabel,
    NULL AS PopularTags,
    0 AS CommentsAfterFirstDay,
    NULL AS AverageAnswerScore,
    'Regular' AS OwnerStatus
FROM Posts p
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN PostScores ps ON ps.PostId = p.Id
WHERE p.PostTypeId = 2
  AND p.CreationDate > CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 month'
ORDER BY 
    PopularityLabel DESC,
    Score DESC,
    CreationDate DESC
LIMIT 100;