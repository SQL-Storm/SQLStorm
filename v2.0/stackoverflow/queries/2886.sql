-- {"query": "2886.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1244}
WITH RECURSIVE RecursiveTagPosts AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Title,
        p.Tags
    FROM Tags t
    JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.PostTypeId = 1
    UNION ALL
    SELECT
        r.TagId,
        r.TagName,
        a.Id AS PostId,
        a.PostTypeId,
        a.Score,
        a.ViewCount,
        a.CreationDate,
        a.OwnerUserId,
        a.Title,
        a.Tags
    FROM RecursiveTagPosts r
    JOIN Posts a ON a.ParentId = r.PostId AND a.PostTypeId = 2
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        count(distinct b.Id) AS BadgeCount,
        sum(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        sum(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        sum(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
LatestEdits AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorUserId,
        ph.UserDisplayName AS EditorName,
        ph.Comment AS EditComment,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,10,11)
    ORDER BY ph.PostId, ph.CreationDate DESC
),
ActiveUsersRanked AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        ub.BadgeCount,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        row_number() OVER (ORDER BY u.Reputation DESC NULLS LAST, ub.GoldBadges DESC NULLS LAST) AS RankByRep,
        dense_rank() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS LocationRepRank
    FROM Users u
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    WHERE u.Reputation > 1000 AND u.LastAccessDate > (cast('2024-10-01 12:34:56' AS timestamp) - INTERVAL '90 days')
),
TopScoredPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        COALESCE(u.DisplayName, p.OwnerDisplayName, 'unknown') AS OwnerName,
        p.CreationDate,
        (
            SELECT string_agg(tag, ', ' ORDER BY tag)
            FROM (
                SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2)), '><')) AS tag
            ) tags
        ) AS ParsedTags,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1 AND p.Score > 50
),
CloseReasonsCount AS (
    SELECT 
        crt.Name AS CloseReason,
        count(*) AS TimesClosed
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS integer) = crt.Id
    WHERE ph.PostHistoryTypeId = 10
    GROUP BY crt.Name
),
DuplicatesWithAnswers AS (
    SELECT
        pl.PostId AS DuplicateId,
        pl.RelatedPostId AS OriginalId,
        po.Title AS OriginalTitle,
        count(a.Id) FILTER (WHERE a.PostTypeId = 2) AS OriginalAnswerCount,
        avg(a.Score) FILTER (WHERE a.PostTypeId = 2) AS OriginalAvgAnswerScore
    FROM PostLinks pl
    JOIN Posts po ON po.Id = pl.RelatedPostId AND po.PostTypeId = 1
    LEFT JOIN Posts a ON a.ParentId = po.Id AND a.PostTypeId = 2
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId, pl.RelatedPostId, po.Title
)
SELECT 
    ts.Id AS QuestionId,
    ts.Title,
    ts.Score,
    ts.ViewCount,
    ts.OwnerUserId,
    ts.OwnerName,
    ts.CreationDate,
    ts.ParsedTags,
    ts.PostStatus,
    cu.RankByRep AS OwnerReputationRank,
    cu.GoldBadges,
    cu.SilverBadges,
    cu.BronzeBadges,
    le.EditDate AS LastEditDate,
    le.EditorName AS LastEditor,
    cr.TimesClosed,
    dup.OriginalTitle AS DuplicateOf,
    dup.OriginalAnswerCount,
    dup.OriginalAvgAnswerScore
FROM TopScoredPosts ts
LEFT JOIN ActiveUsersRanked cu ON cu.Id = ts.OwnerUserId
LEFT JOIN LatestEdits le ON le.PostId = ts.Id
LEFT JOIN CloseReasonsCount cr ON TRUE
LEFT JOIN DuplicatesWithAnswers dup ON dup.DuplicateId = ts.Id
WHERE EXISTS (
    SELECT 1 FROM RecursiveTagPosts rtp 
    WHERE rtp.PostId = ts.Id AND rtp.Score > 10 AND rtp.TagName IN ('sql', 'performance', 'query')
)
ORDER BY ts.Score DESC NULLS LAST, ts.ViewCount DESC NULLS LAST
LIMIT 100;