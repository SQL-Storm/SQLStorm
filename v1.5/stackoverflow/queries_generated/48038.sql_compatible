WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) as rn
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '1 year'
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 END) AS TitleEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 END) AS TagEdits,
        COUNT(CASE WHEN c.Id IS NOT NULL THEN 1 END) AS CommentsMade,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesGiven
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    WHERE u.Id IN (SELECT OwnerUserId FROM RankedPosts)
    GROUP BY u.Id, u.DisplayName
),
TopPostDetails AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        ua.DisplayName AS OwnerDisplayName,
        ua.BodyEdits,
        ua.TitleEdits,
        ua.TagEdits,
        ua.CommentsMade,
        ua.UpVotesGiven,
        ua.DownVotesGiven
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 100
),
AggregatedStats AS (
    SELECT
        tp.PostId,
        tp.Title,
        tp.CreationDate,
        tp.Score,
        tp.ViewCount,
        tp.OwnerUserId,
        tp.OwnerDisplayName,
        tp.BodyEdits,
        tp.TitleEdits,
        tp.TagEdits,
        tp.CommentsMade,
        tp.UpVotesGiven,
        tp.DownVotesGiven,
        (tp.BodyEdits + tp.TitleEdits + tp.TagEdits) AS TotalEdits,
        (tp.UpVotesGiven + tp.DownVotesGiven) AS TotalVotesCast,
        (tp.ViewCount * tp.Score) AS ViewScoreProduct,
        ROW_NUMBER() OVER (ORDER BY tp.ViewCount DESC) as PostViewRank,
        ROW_NUMBER() OVER (ORDER BY tp.Score DESC) as PostScoreRank,
        ROW_NUMBER() OVER (ORDER BY (tp.BodyEdits + tp.TitleEdits + tp.TagEdits) DESC) as PostEditRank,
        ROW_NUMBER() OVER (ORDER BY tp.CommentsMade DESC) as PostCommentRank
    FROM TopPostDetails tp
)
SELECT
    as_stats.PostId,
    as_stats.Title,
    as_stats.CreationDate,
    as_stats.Score,
    as_stats.ViewCount,
    as_stats.OwnerUserId,
    as_stats.OwnerDisplayName,
    as_stats.BodyEdits,
    as_stats.TitleEdits,
    as_stats.TagEdits,
    as_stats.CommentsMade,
    as_stats.UpVotesGiven,
    as_stats.DownVotesGiven,
    as_stats.TotalEdits,
    as_stats.TotalVotesCast,
    as_stats.ViewScoreProduct,
    as_stats.PostViewRank,
    as_stats.PostScoreRank,
    as_stats.PostEditRank,
    as_stats.PostCommentRank,
    CASE
        WHEN as_stats.PostViewRank <= 10 THEN 'TopView'
        WHEN as_stats.PostScoreRank <= 10 THEN 'TopScore'
        WHEN as_stats.PostEditRank <= 10 THEN 'TopEdit'
        WHEN as_stats.PostCommentRank <= 10 THEN 'TopComment'
        ELSE 'Average'
    END AS PerformanceCategory
FROM AggregatedStats as_stats
ORDER BY as_stats.ViewCount DESC, as_stats.Score DESC, as_stats.TotalEdits DESC;