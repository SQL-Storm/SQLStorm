-- {"query": "724.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1617} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        1 AS Level
    FROM Tags t
    WHERE t.IsRequired = 1
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.ExcerptPostId = r.Id
    WHERE r.Level < 3
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        COALESCE(SUM(p.Score),0) AS TotalPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Class) AS MaxBadgeClass
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostWithLinkAndVotes AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        pl.LinkTypeId,
        v.VoteTypeId,
        v.UserId AS VoteUserId,
        v.BountyAmount
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id AND pl.LinkTypeId = 1
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId IN (2,3) -- UpMod and DownMod only
),
RankedComments AS (
    SELECT
        c.PostId,
        c.Id AS CommentId,
        c.UserId,
        c.Score,
        c.CreationDate,
        ROW_NUMBER() OVER (PARTITION BY c.PostId ORDER BY c.Score DESC, c.CreationDate ASC) AS CommentRank
    FROM Comments c
    WHERE c.Score IS NOT NULL
),
TopComments AS (
    SELECT
        rc.PostId,
        STRING_AGG(rc.CommentId::TEXT || ':' || COALESCE(u.DisplayName, rc.UserDisplayName, 'Unknown'), ', ' ORDER BY rc.CommentRank) AS TopCommentInfo
    FROM RankedComments rc
    LEFT JOIN Users u ON u.Id = rc.UserId
    WHERE rc.CommentRank <= 3
    GROUP BY rc.PostId
),
PostHistoryCloseInfo AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVotesCount,
        MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId = 10) AS LastCloseVoteDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostAggregates AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName AS OwnerName,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalPostScore,
        ups.BadgeCount,
        phci.CloseReasonId,
        phci.CloseVotesCount,
        phci.LastCloseVoteDate,
        tc.TopCommentInfo,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS PostTypeCount
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserPostStats ups ON ups.UserId = p.OwnerUserId
    LEFT JOIN PostHistoryCloseInfo phci ON phci.PostId = p.Id
    LEFT JOIN TopComments tc ON tc.PostId = p.Id
    WHERE p.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
),
DuplicatePosts AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName AS PostOwner,
        u2.DisplayName AS RelatedPostOwner
    FROM PostLinks pl
    LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pl.PostId)
    LEFT JOIN Users u2 ON u2.Id = (SELECT OwnerUserId FROM Posts WHERE Id = pl.RelatedPostId)
    WHERE pl.LinkTypeId = 3 -- Duplicate
),
PopularTags AS (
    SELECT
        UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag,
        COUNT(*) AS UsageCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViewCount
    FROM Posts p
    WHERE p.PostTypeId = 1
    GROUP BY Tag
    HAVING COUNT(*) > 50
),
FinalSelection AS (
    SELECT
        pa.PostId,
        pa.PostTypeId,
        pa.CreationDate,
        pa.Score,
        pa.ViewCount,
        pa.Tags,
        pa.OwnerName,
        pa.QuestionCount,
        pa.AnswerCount,
        pa.TotalPostScore,
        pa.BadgeCount,
        pa.CloseReasonId,
        pa.CloseVotesCount,
        pa.LastCloseVoteDate,
        pa.TopCommentInfo,
        d.RelatedPostId AS DuplicateOfPostId,
        d.RelatedPostOwner,
        pt.Tag,
        pt.UsageCount,
        pt.AvgScore,
        pt.MaxViewCount
    FROM PostAggregates pa
    LEFT JOIN DuplicatePosts d ON d.PostId = pa.PostId
    LEFT JOIN LATERAL (
        SELECT pt.Tag, pt.UsageCount, pt.AvgScore, pt.MaxViewCount
        FROM PopularTags pt
        WHERE pa.Tags LIKE '%' || pt.Tag || '%'
        ORDER BY pt.UsageCount DESC
        LIMIT 1
    ) pt ON TRUE
    WHERE pa.Score > 10
)
SELECT 
    fs.PostId,
    fs.PostTypeId,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.OwnerName,
    fs.QuestionCount,
    fs.AnswerCount,
    fs.TotalPostScore,
    fs.BadgeCount,
    COALESCE(crt.Name, 'N/A') AS CloseReason,
    fs.CloseVotesCount,
    fs.LastCloseVoteDate,
    fs.TopCommentInfo,
    fs.DuplicateOfPostId,
    fs.RelatedPostOwner AS DuplicateOwner,
    fs.Tag AS MostPopularTag,
    fs.UsageCount AS TagUsageCount,
    ROUND(fs.AvgScore::numeric, 2) AS TagAvgScore,
    fs.MaxViewCount AS TagMaxViewCount,
    ROW_NUMBER() OVER (PARTITION BY fs.PostTypeId ORDER BY fs.Score DESC, fs.ViewCount DESC NULLS LAST) AS FinalRank
FROM FinalSelection fs
LEFT JOIN CloseReasonTypes crt ON crt.Id::text = fs.CloseReasonId
ORDER BY fs.PostTypeId, FinalRank
LIMIT 100;
