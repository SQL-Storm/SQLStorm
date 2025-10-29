-- {"query": "2035.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1322} 
WITH RecursiveTagHierarchy (Id, TagName, ParentTagId, Depth) AS (
    SELECT t.Id, t.TagName, NULL::int as ParentTagId, 1 as Depth
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT t2.Id, t2.TagName, r.Id as ParentTagId, r.Depth + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.ExcerptPostId = r.Id
    WHERE r.Depth < 5
),
UserBadgeSummary AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) as UserTopPostRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
),
PostVoteSummary AS (
    SELECT 
        p.Id as PostId,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
        SUM(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
PostCommentSummary AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
QuestionsWithDuplicates AS (
    SELECT DISTINCT p.Id AS QuestionId, pl.RelatedPostId AS DuplicateOfId, pl.CreationDate
    FROM Posts p
    JOIN PostLinks pl ON pl.PostId = p.Id
    WHERE p.PostTypeId = 1 AND pl.LinkTypeId = 3
),
QuestionsWithCloseInfo AS (
    SELECT 
        p.Id AS QuestionId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN COALESCE(ph.Comment::int, 0) END) AS CloseReasonId,
        MIN(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS ClosedDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
    WHERE p.PostTypeId = 1
    GROUP BY p.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LatestBadgeDate,
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    COALESCE(pvs.UpVotes,0) AS UpVotes,
    COALESCE(pvs.DownVotes,0) AS DownVotes,
    COALESCE(pvs.Favorites,0) AS Favorites,
    COALESCE(pvs.TotalBounty,0) AS TotalBounty,
    p.CreationDate AS PostCreationDate,
    COALESCE(cms.CommentCount,0) AS CommentCount,
    COALESCE(cms.AvgCommentLength,0) AS AvgCommentLength,
    cms.LastCommentDate,
    qd.DuplicateOfId,
    qci.CloseReasonId,
    qci.ClosedDate,
    RT.Depth AS TagDepth,
    RT.ParentTagId,
    RT.TagName,
    COUNT(*) OVER (PARTITION BY u.Id) AS TotalPostsByUser,
    AVG(p.Score) OVER (PARTITION BY u.Id) AS AvgScoreByUser,
    LEAD(p.Score) OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS NextHighestScore,
    CASE WHEN p.AcceptedAnswerId = -1 THEN NULL ELSE p.AcceptedAnswerId END AS CleanAcceptedAnswerId,
    (
        SELECT COUNT(*)
        FROM Posts ans
        WHERE ans.ParentId = p.Id AND ans.Score > 10 AND ans.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '6 months')
    ) AS HighScoreRecentAnswersCount,
    STRING_AGG(DISTINCT COALESCE(t.TagName, ''), ',') FILTER (WHERE t.TagName IS NOT NULL) AS PostTags
FROM
    TopPosts p
    INNER JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeSummary ub ON ub.UserId = u.Id
    LEFT JOIN PostVoteSummary pvs ON pvs.PostId = p.Id
    LEFT JOIN PostCommentSummary cms ON cms.PostId = p.Id
    LEFT JOIN QuestionsWithDuplicates qd ON qd.QuestionId = p.Id
    LEFT JOIN QuestionsWithCloseInfo qci ON qci.QuestionId = p.Id
    LEFT JOIN RecursiveTagHierarchy RT ON POSITION('<' || RT.TagName || '>' IN COALESCE(p.Tags,'')) > 0
    LEFT JOIN Tags t ON t.TagName = RT.TagName
WHERE
    u.Reputation > 1000
    AND p.Score > 0
    AND (qci.CloseReasonId IS NULL OR qci.CloseReasonId NOT IN (101,102,103)) -- exclude certain close reasons
ORDER BY
    u.Reputation DESC,
    p.Score DESC
LIMIT 100;