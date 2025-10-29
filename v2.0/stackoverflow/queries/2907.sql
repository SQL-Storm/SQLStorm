-- {"query": "2907.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1551}
WITH RECURSIVE RecursiveTagCount AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS EngagementScore,
        1 AS Depth
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Id = t.ExcerptPostId
    WHERE
        t.TagName IS NOT NULL

    UNION ALL

    SELECT
        t.Id,
        t.TagName,
        rtc.EngagementScore + COALESCE(p.CommentCount, 0),
        rtc.Depth + 1
    FROM
        RecursiveTagCount rtc
    JOIN
        Tags t ON t.Id = rtc.TagId
    LEFT JOIN
        Posts p ON p.Id = t.WikiPostId
    WHERE
        rtc.Depth < 2
),
UserReputations AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY u.Location ORDER BY u.Reputation DESC) AS RankByLocation,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS HighestBadgeClass,
        u.Location
    FROM
        Users u
    LEFT JOIN
        Badges b ON b.UserId = u.Id
    WHERE
        u.Location IS NOT NULL
        AND u.Reputation > 100 
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.Location
),
TopPostsWithDetails AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        p.Tags,
        (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
        (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
        (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByUser
    FROM
        Posts p
    LEFT JOIN
        Users u ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 1
        AND p.Score > 5
        AND p.ViewCount > 100
),
MarkDuplicateRelations AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        p.Title AS RelatedPostTitle
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON lt.Id = pl.LinkTypeId
    JOIN
        Posts p ON p.Id = pl.RelatedPostId
    WHERE 
        lt.Name = 'Duplicate'
),
FilteredPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.UserId,
        us.DisplayName AS EditorName,
        ph.CreationDate,
        ph.Comment,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
    JOIN
        PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
    LEFT JOIN
        Users us ON us.Id = ph.UserId
    WHERE 
        ph.PostHistoryTypeId IN (4,5,6,10,11,19,20)
),
LatestEdits AS (
    SELECT
        PostId,
        HistoryTypeName,
        EditorName,
        CreationDate,
        Comment
    FROM
        FilteredPostHistory
    WHERE
        rn = 1
),
AnswerScoresAndRanks AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        a.OwnerUserId AS AnswerOwnerId,
        u.DisplayName AS AnswerOwnerName,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS RankByScore,
        DENSE_RANK() OVER (PARTITION BY a.ParentId ORDER BY a.OwnerUserId) AS OwnerRank
    FROM
        Posts a
    LEFT JOIN
        Users u ON u.Id = a.OwnerUserId
    WHERE
        a.PostTypeId = 2
)
SELECT 
    tp.Id AS QuestionId,
    tp.Title,
    tp.CreationDate,
    tp.Score AS QuestionScore,
    tp.ViewCount,
    tp.OwnerUserId,
    tp.OwnerName,
    tp.Tags,
    tp.CommentCount,
    tp.UpVotes,
    tp.DownVotes,
    ur.DisplayName AS TopUserInLocation,
    ur.Location,
    ur.Reputation AS UserReputation,
    ur.BadgeCount,
    ur.HighestBadgeClass,
    le.HistoryTypeName AS LastEditType,
    le.EditorName AS LastEditor,
    le.CreationDate AS LastEditDate,
    mdr.RelatedPostId AS DuplicateOfPostId,
    mdr.RelatedPostTitle AS DuplicateOfPostTitle,
    asa.AnswerId,
    asa.AnswerScore,
    asa.AnswerOwnerName,
    asa.RankByScore AS AnswerRankByScore
FROM
    TopPostsWithDetails tp
LEFT JOIN
    UserReputations ur ON ur.Id = tp.OwnerUserId AND ur.RankByLocation = 1
LEFT JOIN
    LatestEdits le ON le.PostId = tp.Id
LEFT JOIN
    MarkDuplicateRelations mdr ON mdr.PostId = tp.Id
LEFT JOIN
    AnswerScoresAndRanks asa ON asa.QuestionId = tp.Id AND asa.RankByScore = 1
WHERE
    (tp.UpVotes - tp.DownVotes) > 5
    AND (
        LOWER(tp.Tags) LIKE '%<sql>%'
        OR LOWER(tp.Tags) LIKE '%<database>%'
    )

UNION

SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerName,
    p.Tags,
    (SELECT COUNT(1) FROM Comments c WHERE c.PostId = p.Id) AS CommentCount,
    (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotes,
    (SELECT COUNT(1) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotes,
    ur.DisplayName,
    ur.Location,
    ur.Reputation,
    ur.BadgeCount,
    ur.HighestBadgeClass,
    NULL AS LastEditType,
    NULL AS LastEditor,
    NULL AS LastEditDate,
    NULL AS DuplicateOfPostId,
    NULL AS DuplicateOfPostTitle,
    NULL AS AnswerId,
    NULL AS AnswerScore,
    NULL AS AnswerOwnerName,
    NULL AS AnswerRankByScore
FROM
    Posts p
LEFT JOIN
    Users u ON u.Id = p.OwnerUserId
LEFT JOIN
    UserReputations ur ON ur.Id = p.OwnerUserId
WHERE
    p.PostTypeId = 1
    AND p.Score > 100
    AND NOT EXISTS (
        SELECT 1
        FROM PostLinks pl2
        WHERE pl2.PostId = p.Id AND pl2.LinkTypeId = 3
    )
ORDER BY
    QuestionScore DESC,
    ViewCount DESC,
    CreationDate DESC
LIMIT 100;