-- {"query": "3081.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1142} 
WITH AnswerCounts AS (
    SELECT
        p.Id AS PostId,
        p.Title AS PostTitle,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        ac.AnswerCount,
        u.Reputation,
        u.DisplayName,
        COALESCE(bt.BadgesCount, 0) AS BadgeCount,
        NULLIF(vt.VoteSum, 0) AS VoteScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank
    FROM
        Posts p
        LEFT JOIN (
            SELECT ParentId, COUNT(*) AS AnswerCount
            FROM Posts
            WHERE PostTypeId = 2
            GROUP BY ParentId
        ) ac ON p.Id = ac.ParentId
        LEFT JOIN Users u ON p.OwnerUserId = u.Id
        LEFT JOIN (
            SELECT UserId, COUNT(*) AS BadgesCount
            FROM Badges
            GROUP BY UserId
        ) bt ON u.Id = bt.UserId
        LEFT JOIN (
            SELECT PostId, SUM(CASE WHEN VoteTypeId IN (2, 7) THEN 1 WHEN VoteTypeId IN (3, 12, 14) THEN -1 ELSE 0 END) AS VoteSum
            FROM Votes
            GROUP BY PostId
        ) vt ON p.Id = vt.PostId
        LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= '2023-01-01'
),
ActiveTags AS (
    SELECT
        t.TagName,
        COUNT(*) AS TagUsageCount,
        STRING_AGG(t.TagName, ', ' ORDER BY t.TagName) AS TagNames
    FROM
        Tags t
    GROUP BY
        t.TagName
),
PostHistorySummary AS (
    SELECT
        ph.PostId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)) AS RevisionCount,
        MAX(ph.CreationDate) AS LastRevisionDate
    FROM
        PostHistory ph
    GROUP BY
        ph.PostId
),
LinkedPosts AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName,
        pl.CreationDate AS LinkCreationDate
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        lt.Name IN ('Linked', 'Duplicate')
),
RecentComments AS (
    SELECT
        c.PostId,
        c.Text,
        c.CreationDate,
        c.UserDisplayName
    FROM
        Comments c
    WHERE
        c.CreationDate >= NOW() - INTERVAL '30 days'
),
UserReputation AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(b.Id) AS BadgeCount,
        MAX(b.Date) AS LatestBadgeDate
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName
),
FullPostData AS (
    SELECT
        ac.PostId,
        ac.PostTitle,
        ac.CreationDate,
        ac.Score,
        ac.ViewCount,
        ac.OwnerUserId,
        ac.Tags,
        ac.AnswerCount,
        ac.Reputation,
        ac.DisplayName,
        ac.BadgeCount,
        ac.VoteScore,
        ac.CommentCount,
        ac.UserPostRank,
        ht.RevisionCount,
        ht.LastRevisionDate,
        ARRAY_AGG(lp.RelatedPostId) FILTER (WHERE lp.LinkTypeName = 'Duplicate') AS DuplicateLinks,
        ARRAY_AGG(lp.RelatedPostId) FILTER (WHERE lp.LinkTypeName = 'Linked') AS LinkedPosts,
        ARRAY_AGG(rc.Text) AS RecentComments,
        ur.Reputation AS OwnerReputation,
        ur.BadgeCount AS OwnerBadgeCount
    FROM
        AnswerCounts ac
        LEFT JOIN PostHistorySummary ht ON ac.PostId = ht.PostId
        LEFT JOIN LinkedPosts lp ON ac.PostId = lp.PostId
        LEFT JOIN RecentComments rc ON ac.PostId = rc.PostId
        LEFT JOIN UserReputation ur ON ac.OwnerUserId = ur.UserId
    GROUP BY
        ac.PostId,
        ac.PostTitle,
        ac.CreationDate,
        ac.Score,
        ac.ViewCount,
        ac.OwnerUserId,
        ac.Tags,
        ac.AnswerCount,
        ac.Reputation,
        ac.DisplayName,
        ac.BadgeCount,
        ac.VoteScore,
        ac.CommentCount,
        ac.UserPostRank,
        ht.RevisionCount,
        ht.LastRevisionDate,
        ur.Reputation,
        ur.BadgeCount
)
SELECT
    *
FROM
    FullPostData
WHERE
    OwnerReputation IS NOT NULL
    AND AnswerCount > 0
    AND (Reputation BETWEEN 1000 AND 5000 OR BadgeCount >= 5)
    AND 'sql' = ANY (string_to_array(Tags, ', '))
    AND LastRevisionDate IS NOT NULL
ORDER BY
    CreationDate DESC
LIMIT 100;