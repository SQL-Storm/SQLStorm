-- {"query": "1376.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1601} 

WITH RecursiveTaggedPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.Tags,
        array_to_string(array_agg(DISTINCT ut.Name), ', ') AS UniqueTagNames
    FROM 
        Posts p
        LEFT JOIN LATERAL
            unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS tagname ON TRUE
        LEFT JOIN Tags t ON t.TagName = tagname
        LEFT JOIN Users ut ON ut.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1 -- Questions only
        AND p.CreationDate >= now() - interval '1 year'
    GROUP BY 
        p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.Tags

    UNION ALL

    SELECT 
        p2.Id,
        p2.Title,
        p2.CreationDate,
        p2.OwnerUserId,
        p2.Score,
        p2.Tags,
        rtp.UniqueTagNames
    FROM 
        Posts p2
        JOIN RecursiveTaggedPosts rtp ON p2.ParentId = rtp.Id
    WHERE
        p2.PostTypeId = 2 -- Answers
), LatestPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6) -- Title, Body or Tags edits
), UserBadgeAggregates AS (
    SELECT
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount,
        AVG(EXTRACT(EPOCH FROM now() - b.Date)/86400) AS AvgDaysSinceBadge
    FROM
        Badges b
    GROUP BY
        b.UserId, b.Class
), UserReputationBuckets AS (
    SELECT
        u.Id,
        CASE 
            WHEN u.Reputation >= 100000 THEN 'Legendary'
            WHEN u.Reputation BETWEEN 20000 AND 99999 THEN 'Expert'
            WHEN u.Reputation BETWEEN 5000 AND 19999 THEN 'Intermediate'
            ELSE 'Novice'
        END AS RepBucket
    FROM
        Users u
)
SELECT 
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    usr.DisplayName AS Owner,
    p.Score,
    p.ViewCount, 
    p.AnswerCount,
    COALESCE(ubl.BadgeCount, 0) AS BronzeBadges,
    COALESCE(ubs.BadgeCount, 0) AS SilverBadges,
    COALESCE(ubg.BadgeCount, 0) AS GoldBadges,
    rep.RepBucket,
    p.Tags,
    STRING_AGG(DISTINCT lt.Name || ' (LinkType)', ', ') AS IncomingLinkTypes,
    COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(DISTINCT c.Id) AS CommentCount,
    MAX(lpe.CreationDate) FILTER (WHERE lpe.rn = 1) AS LastEditDate,
    MAX(pl.CreationDate) AS LatestLinkDate,
    STRING_AGG(DISTINCT CASE WHEN c.Score > 3 THEN c.Text END, ' | ') AS TopCommentsSummary,
    LEAD(p.Score) OVER (ORDER BY p.Score DESC) - p.Score AS NextHigherScoreDiff,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
    END AS Status,
    CASE 
        WHEN EXISTS (SELECT 1 FROM Posts a WHERE a.ParentId = p.Id AND a.Score > p.Score * 0.8) THEN 'Contested' 
        ELSE 'Dominant'
    END AS AnswerCompetitionStatus,
    -- Correlated subquery with NULL logics and string expressions:
    (SELECT STRING_AGG(ph.Comment, ' | ')
     FROM PostHistory ph
     WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL AND ph.Comment <> ''
    ) AS CloseReasons,
    -- Complex predicate with NULLs:
    CASE 
        WHEN p.AcceptedAnswerId IS NOT NULL THEN
            (SELECT u2.DisplayName 
             FROM Posts a2 
             LEFT JOIN Users u2 ON u2.Id = a2.OwnerUserId
             WHERE a2.Id = p.AcceptedAnswerId)
        ELSE 'No accepted answer'
    END AS AcceptedAnswerOwner,
    -- Complicated string and arithmetic work with NULL protection:
    (COALESCE(p.Score, 0) * COALESCE(p.ViewCount, 1) / NULLIF(NULLIF(1 + p.AnswerCount,0),0) + COALESCE(p.FavoriteCount,0) * 10)
        +
     COALESCE((SELECT SUM(v2.BountyAmount) FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId IN (8,9)), 0)
    AS WeightedScore
FROM 
    RecursiveTaggedPosts p
    LEFT JOIN Users usr ON p.OwnerUserId = usr.Id
    LEFT JOIN UserBadgeAggregates ubl ON ubl.UserId = usr.Id AND ubl.Class = 3
    LEFT JOIN UserBadgeAggregates ubs ON ubs.UserId = usr.Id AND ubs.Class = 2
    LEFT JOIN UserBadgeAggregates ubg ON ubg.UserId = usr.Id AND ubg.Class = 1
    LEFT JOIN UserReputationBuckets rep ON rep.Id = usr.Id
    LEFT JOIN PostLinks pl ON pl.RelatedPostId = p.Id
    LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN LatestPostEdits lpe ON lpe.PostId = p.Id AND lpe.rn = 1
WHERE
    p.Score > 10
    AND p.CreationDate > now() - interval '1 year'
GROUP BY 
    p.Id, p.Title, p.CreationDate, usr.DisplayName, p.Score, p.ViewCount, p.AnswerCount, p.Tags, p.ClosedDate, p.AcceptedAnswerId,
    ubl.BadgeCount, ubs.BadgeCount, ubg.BadgeCount, rep.RepBucket, lpe.CreationDate
ORDER BY
    WeightedScore DESC
LIMIT 50

UNION

SELECT
    p2.Id,
    p2.Title,
    p2.CreationDate,
    COALESCE(u.DisplayName, p2.OwnerDisplayName) AS Owner,
    p2.Score,
    p2.ViewCount,
    0 AS AnswerCount,
    0, 0, 0, 'Novice' AS RepBucket,
    p2.Tags,
    NULL,
    0, 0, NULL, NULL, NULL, NULL, 'Answer',
    NULL,
    NULL,
    NULL
FROM
    Posts p2
    LEFT JOIN Users u ON u.Id = p2.OwnerUserId
WHERE
    p2.PostTypeId = 2
    AND p2.CreationDate > now() - interval '1 year'
ORDER BY
    p2.Score DESC
LIMIT 10;
