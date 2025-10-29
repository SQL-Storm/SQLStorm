WITH PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.CreationDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        p.Body,
        COALESCE(p.AcceptedAnswerId, 0) AS AcceptedAnswerId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END AS ScoreCategory,
        CAST((EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 86400) AS INTEGER) AS DaysActive,
        COALESCE(p.AnswerCount, 0) - COALESCE(p.CommentCount, 0) AS NetVotes,
        LENGTH(p.Body) AS BodyLength,
        -- count of '<' occurs in tags approximates number of tags; for SQL standard use (length - length(replace)) / length('<') but here use regexp_count if available else fallback
        COALESCE(
          CASE WHEN POSITION('<' IN COALESCE(p.Tags, '')) > 0 
               THEN (LENGTH(COALESCE(p.Tags, '')) - LENGTH(REPLACE(COALESCE(p.Tags, ''), '<', '')) )
               ELSE 0 END
        , 0) AS TagCount,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsClosed,
        CASE 
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 
            ELSE 0 
        END AS IsCommunityOwned
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        CAST((EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate)) / 86400) AS INTEGER) AS DaysSinceCreation,
        CASE 
            WHEN u.Reputation >= 10000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Intermediate'
            ELSE 'Beginner'
        END AS UserLevel,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate
),
DetailedPostAnalysis AS (
    SELECT 
        ps.Id AS PostId,
        ps.PostTypeId,
        ps.OwnerUserId,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CommentCount,
        ps.CreationDate,
        ps.LastActivityDate,
        ps.Title,
        ps.Tags,
        ps.Body,
        ps.AcceptedAnswerId,
        ps.PostType,
        ps.ScoreCategory,
        ps.DaysActive,
        ps.NetVotes,
        ps.BodyLength,
        ps.TagCount,
        ps.IsClosed,
        ps.IsCommunityOwned,
        ROW_NUMBER() OVER (PARTITION BY ps.OwnerUserId ORDER BY ps.Score DESC) AS UserPostRank,
        RANK() OVER (ORDER BY ps.Score DESC) AS GlobalPostRank,
        DENSE_RANK() OVER (ORDER BY ps.ViewCount DESC) AS ViewRank,
        AVG(ps.Score) OVER (PARTITION BY ps.OwnerUserId) AS AvgScorePerUser,
        MAX(ps.ViewCount) OVER (PARTITION BY ps.OwnerUserId) AS MaxViewsPerUser,
        CASE 
            WHEN ps.BodyLength > 1000 THEN 'Long'
            WHEN ps.BodyLength > 500 THEN 'Medium'
            ELSE 'Short'
        END AS BodyLengthCategory,
        CASE 
            WHEN ps.TagCount >= 3 THEN 'Many'
            WHEN ps.TagCount >= 1 THEN 'Few'
            ELSE 'None'
        END AS TagCategory,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 2), 0
        ) AS UpvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = ps.Id AND v.VoteTypeId = 3), 0
        ) AS DownvoteCount,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = ps.Id), 0
        ) AS CommentCountOnPost,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Name LIKE '%Nice%'), 0
        ) AS NiceBadgeCount,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Name LIKE '%Good%'), 0
        ) AS GoodBadgeCount,
        COALESCE(
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = ps.OwnerUserId AND b.Name LIKE '%Great%'), 0
        ) AS GreatBadgeCount
    FROM PostStats ps
),
CombinedData AS (
    SELECT 
        dpa.PostId,
        dpa.PostTypeId,
        dpa.OwnerUserId,
        dpa.Score,
        dpa.ViewCount,
        dpa.AnswerCount,
        dpa.CommentCount,
        dpa.CreationDate,
        dpa.LastActivityDate,
        dpa.Title,
        dpa.Tags,
        dpa.Body,
        dpa.AcceptedAnswerId,
        dpa.PostType,
        dpa.ScoreCategory,
        dpa.DaysActive,
        dpa.NetVotes,
        dpa.BodyLength,
        dpa.TagCount,
        dpa.IsClosed,
        dpa.IsCommunityOwned,
        dpa.UserPostRank,
        dpa.GlobalPostRank,
        dpa.ViewRank,
        dpa.AvgScorePerUser,
        dpa.MaxViewsPerUser,
        dpa.BodyLengthCategory,
        dpa.TagCategory,
        dpa.UpvoteCount,
        dpa.DownvoteCount,
        dpa.CommentCountOnPost,
        dpa.NiceBadgeCount,
        dpa.GoodBadgeCount,
        dpa.GreatBadgeCount,
        ua.DisplayName,
        ua.Reputation,
        ua.Views AS UserViews,
        ua.UpVotes AS UserUpVotes,
        ua.DownVotes AS UserDownVotes,
        ua.UserCreationDate,
        ua.LastAccessDate AS UserLastAccessDate,
        ua.DaysSinceCreation,
        ua.UserLevel,
        ua.PostCount,
        ua.CommentCount AS UserCommentCount,
        ua.BadgeCount,
        CASE 
            WHEN dpa.ViewRank <= 100 THEN 'Top 100 Views'
            WHEN dpa.ViewRank <= 500 THEN 'Top 500 Views'
            WHEN dpa.ViewRank <= 1000 THEN 'Top 1000 Views'
            ELSE 'Other'
        END AS ViewRankCategory
    FROM DetailedPostAnalysis dpa
    LEFT JOIN UserActivity ua ON dpa.OwnerUserId = ua.UserId
    WHERE ua.UserId IS NOT NULL 
      AND dpa.Score > 0 
      AND dpa.ViewCount > 0
    ORDER BY dpa.Score DESC
)
SELECT 
    cd.PostId,
    cd.PostTypeId,
    cd.OwnerUserId,
    cd.Score,
    cd.ViewCount,
    cd.AnswerCount,
    cd.CommentCount,
    cd.CreationDate,
    cd.LastActivityDate,
    cd.Title,
    cd.Tags,
    cd.Body,
    cd.AcceptedAnswerId,
    cd.PostType,
    cd.ScoreCategory,
    cd.DaysActive,
    cd.NetVotes,
    cd.BodyLength,
    cd.TagCount,
    cd.IsClosed,
    cd.IsCommunityOwned,
    cd.UserPostRank,
    cd.GlobalPostRank,
    cd.ViewRank,
    cd.AvgScorePerUser,
    cd.MaxViewsPerUser,
    cd.BodyLengthCategory,
    cd.TagCategory,
    cd.UpvoteCount,
    cd.DownvoteCount,
    cd.CommentCountOnPost,
    cd.NiceBadgeCount,
    cd.GoodBadgeCount,
    cd.GreatBadgeCount,
    cd.DisplayName,
    cd.Reputation,
    cd.UserViews,
    cd.UserUpVotes,
    cd.UserDownVotes,
    cd.UserCreationDate,
    cd.UserLastAccessDate,
    cd.DaysSinceCreation,
    cd.UserLevel,
    cd.PostCount,
    cd.UserCommentCount,
    cd.BadgeCount,
    cd.ViewRankCategory,
    CONCAT(cd.Title, ' (', cd.PostType, ')') AS TitleWithType,
    CASE 
        WHEN cd.Score >= cd.AvgScorePerUser AND cd.ViewCount > cd.MaxViewsPerUser THEN 'High Performance'
        WHEN cd.Score < cd.AvgScorePerUser AND cd.ViewCount <= cd.MaxViewsPerUser THEN 'Low Performance'
        ELSE 'Average Performance'
    END AS PerformanceCategory,
    CASE 
        WHEN cd.DaysActive BETWEEN 1 AND 30 THEN 'Recent'
        WHEN cd.DaysActive BETWEEN 31 AND 90 THEN 'Active'
        WHEN cd.DaysActive > 90 THEN 'Long Term'
        ELSE 'New'
    END AS ActivityCategory,
    ROUND(
        (cd.UpvoteCount * 1.0 / NULLIF(cd.UpvoteCount + cd.DownvoteCount, 0)) * 100, 
        2
    ) AS UpvotePercentage,
    CONCAT(
        'User:', cd.OwnerUserId, 
        '|Post:', cd.PostId,
        '|Views:', cd.ViewCount,
        '|Score:', cd.Score,
        '|Category:', cd.ViewRankCategory
    ) AS PostSummary,
    CASE 
        WHEN cd.BadgeCount >= 10 THEN 'Veteran'
        WHEN cd.BadgeCount >= 5 THEN 'Experienced'
        WHEN cd.BadgeCount >= 1 THEN 'Beginner'
        ELSE 'No Badges'
    END AS BadgeStatus,
    CASE 
        WHEN cd.PostCount > 50 AND cd.BadgeCount > 20 THEN 'Elite Contributor'
        WHEN cd.PostCount > 25 AND cd.BadgeCount > 10 THEN 'Active Contributor'
        WHEN cd.PostCount > 10 THEN 'Regular Contributor'
        ELSE 'New Contributor'
    END AS ContributionLevel
FROM CombinedData cd
WHERE cd.PostTypeId IN (1, 2)
  AND cd.UserLevel IN ('Expert', 'Intermediate')
  AND cd.ViewRankCategory IN ('Top 100 Views', 'Top 500 Views')
  AND cd.ScoreCategory IN ('High', 'Medium')
  AND cd.BodyLength > 200
  AND (
    cd.AcceptedAnswerId > 0 
    OR (cd.PostTypeId = 1 AND cd.AnswerCount > 0)
  )
  AND cd.DaysActive BETWEEN 1 AND 365
ORDER BY cd.Score DESC, cd.ViewCount DESC
LIMIT 1000;