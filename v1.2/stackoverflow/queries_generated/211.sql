-- {"query": "211.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1667} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.TagPath || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.Id <> r.Id AND t2.Count < r.Count
    WHERE r.Level < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
PostActivityWindow AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RecentPostRank,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
        MAX(p.ViewCount) OVER (PARTITION BY p.OwnerUserId) AS MaxUserViewCount
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
TopPostsWithComments AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        c.CommentCount,
        c.LatestCommentDate,
        c.LatestCommentText,
        c.LatestCommentUserId,
        c.LatestCommentUserDisplayName
    FROM Posts p
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate,
            MAX(Text) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LatestCommentText,
            MAX(UserId) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LatestCommentUserId,
            MAX(UserDisplayName) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LatestCommentUserDisplayName
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.Score > 10 AND p.CreationDate > NOW() - INTERVAL '1 year'
),
DuplicateLinkAnalysis AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        COUNT(*) AS DuplicateCount,
        MAX(pl.CreationDate) AS LastDuplicateDate
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- Duplicate
    GROUP BY pl.PostId, pl.RelatedPostId
),
UserReputationRank AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
),
FinalSelection AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        u.DisplayName AS OwnerName,
        u.Reputation,
        u.LastAccessDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        da.DuplicateCount,
        da.LastDuplicateDate,
        c.CommentCount,
        c.LatestCommentDate,
        c.LatestCommentText,
        c.LatestCommentUserDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS OwnerPostRank,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus,
        -- Complex string manipulation: extract first tag from Tags string (format: <tag1><tag2><tag3>)
        COALESCE(NULLIF(SUBSTRING(p.Tags FROM '<([^>]+)>'), ''), 'NoTag') AS FirstTag,
        -- Calculate days since last activity or creation if last activity is null
        EXTRACT(DAY FROM COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate) AS DaysActive,
        -- Correlated subquery: count of answers for question
        (SELECT COUNT(*) FROM Posts ans WHERE ans.ParentId = p.Id AND ans.PostTypeId = 2) AS AnswerCountCorrelated
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeStats ub ON ub.UserId = u.Id
    LEFT JOIN DuplicateLinkAnalysis da ON da.PostId = p.Id
    LEFT JOIN (
        SELECT
            PostId,
            COUNT(*) AS CommentCount,
            MAX(CreationDate) AS LatestCommentDate,
            MAX(Text) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LatestCommentText,
            MAX(UserDisplayName) FILTER (WHERE CreationDate = MAX(CreationDate) OVER (PARTITION BY PostId)) AS LatestCommentUserDisplayName
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = p.Id
    WHERE p.PostTypeId = 1 -- Questions only
)
SELECT
    fs.PostId,
    fs.Title,
    fs.FirstTag,
    fs.Score,
    fs.ViewCount,
    fs.AnswerCount,
    fs.AnswerCountCorrelated,
    fs.FavoriteCount,
    fs.OwnerName,
    fs.Reputation,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.TagBasedBadges,
    fs.DuplicateCount,
    fs.LastDuplicateDate,
    fs.CommentCount,
    fs.LatestCommentDate,
    fs.LatestCommentUserDisplayName,
    fs.PostStatus,
    fs.DaysActive,
    -- Window function: cumulative sum of scores over posts ordered by creation date
    SUM(fs.Score) OVER (ORDER BY fs.PostId ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
    -- Conditional complex expression: weighted score factoring badges and reputation
    (fs.Score * 1.0) + (fs.GoldBadges * 5) + (fs.SilverBadges * 3) + (fs.BronzeBadges * 1) + (fs.Reputation / 1000.0) AS WeightedScore,
    -- NULL logic: if no comments, show 'No comments' else latest comment text truncated to 100 chars
    COALESCE(NULLIF(SUBSTRING(fs.LatestCommentText FROM 1 FOR 100), ''), 'No comments') AS LatestCommentSnippet
FROM FinalSelection fs
WHERE fs.Score > 20
ORDER BY WeightedScore DESC, fs.ViewCount DESC
LIMIT 100;
