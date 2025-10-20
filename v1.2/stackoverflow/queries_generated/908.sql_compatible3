WITH RECURSIVE RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        1 AS Level,
        CAST(ARRAY[t.TagName] AS varchar[]) AS Path
    FROM Tags t
    WHERE t.IsModeratorOnly = false AND t.IsRequired = false
    UNION ALL
    SELECT 
        c.Id,
        c.TagName,
        r.Level + 1,
        r.Path || c.TagName
    FROM Tags c
    JOIN RecursiveTagHierarchy r ON c.Id = (
        SELECT pst.RelatedPostId
        FROM PostLinks pst
        JOIN Posts p1 ON p1.Id = pst.PostId AND p1.PostTypeId = 1
        JOIN Posts p2 ON p2.Id = pst.RelatedPostId AND p2.PostTypeId = 1
        WHERE p1.Tags LIKE '%' || r.TagName || '%'
          AND pst.LinkTypeId = 1
        LIMIT 1
    ) AND NOT c.TagName = ANY(r.Path)
    WHERE r.Level < 3
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        COALESCE(SUM(vote_counts.UpVotes),0) AS TotalUpVotes,
        COALESCE(SUM(vote_counts.DownVotes),0) AS TotalDownVotes,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY PostId
    ) vote_counts ON vote_counts.PostId = p.Id
    GROUP BY u.Id, u.DisplayName
),
PostWithRank AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        DENSE_RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS ScoreRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RecentRank,
        p.CreationDate
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
TopPosts AS (
    SELECT * FROM PostWithRank
    WHERE ScoreRank <= 10 OR RecentRank <= 10
),
BadgeCounts AS (
    SELECT 
        b.UserId,
        b.Class,
        COUNT(*) AS BadgeCount
    FROM Badges b
    GROUP BY b.UserId, b.Class
),
UserBadgeSummary AS (
    SELECT 
        bc.UserId,
        MAX(CASE WHEN bc.Class = 1 THEN bc.BadgeCount ELSE 0 END) AS GoldBadges,
        MAX(CASE WHEN bc.Class = 2 THEN bc.BadgeCount ELSE 0 END) AS SilverBadges,
        MAX(CASE WHEN bc.Class = 3 THEN bc.BadgeCount ELSE 0 END) AS BronzeBadges
    FROM BadgeCounts bc
    GROUP BY bc.UserId
),
ComplexAggregates AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        u.DisplayName AS OwnerName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.TotalUpVotes,
        ua.TotalDownVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        COALESCE(phc.ClosedCount,0) AS NumberOfClosures,
        COALESCE(phc.ReopenCount,0) AS NumberOfReopens,
        ph_last.LastEditDate,
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserActivity ua ON ua.UserId = p.OwnerUserId
    LEFT JOIN UserBadgeSummary ub ON ub.UserId = p.OwnerUserId
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS ClosedCount,
            SUM(CASE WHEN PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount
        FROM PostHistory
        GROUP BY PostId
    ) phc ON phc.PostId = p.Id
    LEFT JOIN (
        SELECT 
            Id AS PostId,
            MAX(LastEditDate) AS LastEditDate
        FROM Posts
        GROUP BY Id
    ) ph_last ON ph_last.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
),
FilteredPostsWithComments AS (
    SELECT 
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        MAX(c.Score) AS MaxCommentScore,
        SUM(CASE WHEN c.Score >= 5 THEN 1 ELSE 0 END) AS HighlyRatedComments
    FROM Comments c
    GROUP BY c.PostId
),
FinalData AS (
    SELECT 
        cp.PostId,
        cp.Title,
        cp.Tags,
        cp.OwnerName,
        cp.QuestionsAsked,
        cp.AnswersGiven,
        cp.TotalUpVotes,
        cp.TotalDownVotes,
        cp.GoldBadges,
        cp.SilverBadges,
        cp.BronzeBadges,
        cp.NumberOfClosures,
        cp.NumberOfReopens,
        cp.LastEditDate,
        fpc.CommentCount,
        fpc.MaxCommentScore,
        fpc.HighlyRatedComments,
        CASE 
            WHEN cp.ScoreRank <= 3 THEN 'Top 3'
            WHEN cp.ScoreRank <= 10 THEN 'Top 10'
            ELSE 'Other'
        END AS PerformanceBracket,
        COALESCE(NULLIF(REPLACE(REPLACE(cp.Tags, '><', ','), '<', ''), ''), 'NoTags') AS TagList,
        LENGTH(cp.Title) AS TitleLength,
        (COALESCE(cp.TotalUpVotes,0) - COALESCE(cp.TotalDownVotes,0)) AS NetVotes,
        (COALESCE(cp.QuestionsAsked,0) + COALESCE(cp.AnswersGiven,0)) AS TotalContributions,
        (COALESCE(cp.GoldBadges,0)*3 + COALESCE(cp.SilverBadges,0)*2 + COALESCE(cp.BronzeBadges,0)) AS BadgeScore
    FROM ComplexAggregates cp
    LEFT JOIN FilteredPostsWithComments fpc ON fpc.PostId = cp.PostId
)
SELECT 
    fd.PerformanceBracket,
    fd.TagList,
    COUNT(DISTINCT fd.PostId) AS CountOfPosts,
    AVG(fd.TitleLength) AS AvgTitleLength,
    AVG(fd.NetVotes) AS AvgNetVotes,
    AVG(fd.TotalContributions) AS AvgUserContributions,
    AVG(fd.BadgeScore) AS AvgBadgeScore,
    SUM(COALESCE(fd.CommentCount,0)) AS TotalComments,
    SUM(COALESCE(fd.HighlyRatedComments,0)) AS TotalHighlyRatedComments,
    STRING_AGG(DISTINCT fd.OwnerName, ', ') FILTER (WHERE fd.OwnerName IS NOT NULL) AS SampleOwners
FROM FinalData fd
WHERE fd.Title IS NOT NULL
GROUP BY fd.PerformanceBracket, fd.TagList
ORDER BY fd.PerformanceBracket, CountOfPosts DESC;