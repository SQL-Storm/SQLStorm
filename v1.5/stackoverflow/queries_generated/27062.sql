-- {"query": "27062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1840} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation, u.DisplayName, u.CreationDate
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS PostCount,
        SUM(p.ViewCount) AS TotalViews,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(p.Title, ', ') AS RecentTitles
    FROM
        Tags t
    LEFT JOIN
        Posts p ON t.Id = ANY(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), ''><''))
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        PostCount DESC
    LIMIT 10
),
RecentPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        u.DisplayName AS EditorName,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextEditDate
    FROM
        PostHistory ph
    JOIN
        Users u ON ph.UserId = u.Id
    WHERE
        ph.PostHistoryTypeId IN (5, 6, 10, 11, 12)
    AND
        ph.CreationDate > NOW() - INTERVAL '30 days'
),
ComplexPostMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName AS OwnerName,
        COALESCE(a.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COALESCE(a.Title, '') AS AcceptedAnswerTitle,
        COUNT(c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(ph.CreationDate) AS LastEditDate,
        COALESCE(ph.UserId, -1) AS LastEditorId,
        COALESCE(ph.UserDisplayName, '') AS LastEditorName,
        COALESCE(l.RelatedPostId, -1) AS RelatedPostId,
        COALESCE(l.LinkTypeId, -1) AS LinkTypeId
    FROM
        Posts p
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Posts a ON p.AcceptedAnswerId = a.Id
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        PostLinks l ON p.Id = l.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount,
        p.OwnerUserId, u.DisplayName, a.AcceptedAnswerId, a.Title,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        l.RelatedPostId,
        l.LinkTypeId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.LastPostActivityDate,
    ua.LastCommentDate,
    ua.LastVoteDate,
    ua.LastBadgeDate,
    tt.TagName,
    tt.PostCount,
    tt.TotalViews,
    tt.AverageScore,
    tt.LastPostDate,
    tt.RecentTitles,
    rph.PostId,
    rph.PostHistoryTypeId,
    rph.HistoryDate,
    rph.EditorName,
    rph.PreviousEditDate,
    rph.NextEditDate,
    cpm.PostId,
    cpm.PostTypeId,
    cpm.CreationDate,
    cpm.Score,
    cpm.ViewCount,
    cpm.OwnerName,
    cpm.AcceptedAnswerId,
    cpm.AcceptedAnswerTitle,
    cpm.CommentCount,
    cpm.VoteCount,
    cpm.UpVoteCount,
    cpm.DownVoteCount,
    cpm.LastEditDate,
    cpm.LastEditorId,
    cpm.LastEditorName,
    cpm.RelatedPostId,
    cpm.LinkTypeId
FROM
    UserActivity ua
CROSS JOIN
    TopTags tt
LEFT JOIN
    RecentPostHistory rph ON ua.UserId = rph.UserId
LEFT JOIN
    ComplexPostMetrics cpm ON ua.UserId = cpm.OwnerUserId
WHERE
    ua.TotalPosts > 10
    AND ua.TotalComments > 5
    AND ua.TotalVotes > 20
    AND ua.TotalBadges > 3 and (SELECT COUNT(*) FROM Posts p JOIN ComplexPostMetrics cm ON p.id = cm.postId WHERE cm.ownerName = ua.displayName) > 10
    AND tt.PostCount > 50
    AND rph.PostHistoryTypeId IS NOT NULL
    AND UNACCENT(LOWER(tt.TagName)) LIKE '%' || unaccent(lower('SOFTWARE')) || '%'
ORDER BY
    ua.Reputation DESC,
    tt.PostCount DESC,
    rph.HistoryDate DESC,
    cpm.CreationDate DESC
LIMIT
    50;
