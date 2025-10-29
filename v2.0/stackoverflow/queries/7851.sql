WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        SUM(CASE WHEN p.Score > 0 THEN p.Score ELSE 0 END) AS PositiveScore,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT p.Tags, ';') AS AllTags
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagPerformance AS (
    SELECT 
        t.TagName,
        t.Count,
        COALESCE(p.ViewCount, 0) AS AvgViews,
        COALESCE(p.Score, 0) AS AvgScore,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 500 THEN 'Moderate'
            WHEN t.Count > 100 THEN 'Niche'
            ELSE 'Tiny'
        END AS TagCategory,
        (LAG(t.Count) OVER (ORDER BY t.Count DESC)) - t.Count AS RankDrop
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
    WHERE t.Count > 0
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COUNT(*) AS TotalVotes,
        COUNT(DISTINCT v.PostId) AS PostsVotedOn,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Votes) AS PercentageOfAllVotes,
        DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS ActivityRank,
        CASE 
            WHEN COUNT(*) > (SELECT AVG(VoteCount) FROM (SELECT COUNT(*) AS VoteCount FROM Votes GROUP BY UserId) avg_votes) THEN 'AboveAverage'
            WHEN COUNT(*) > (SELECT AVG(VoteCount) FROM (SELECT COUNT(*) AS VoteCount FROM Votes GROUP BY UserId) avg_votes) * 0.5 THEN 'Average'
            ELSE 'BelowAverage'
        END AS ActivityLevel
    FROM Users u
    INNER JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName
),
ComplexPostAnalysis AS (
    SELECT 
        p.Id,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CHAR_LENGTH(p.Body) AS BodyLength,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 0 THEN 'LowVoted'
            ELSE 'Unvoted'
        END AS VoteCategory,
        CASE 
            WHEN CHAR_LENGTH(p.Title) > 50 THEN 'LongTitle'
            WHEN CHAR_LENGTH(p.Title) > 25 THEN 'MediumTitle'
            ELSE 'ShortTitle'
        END AS TitleLengthCategory,
        CAST(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400 AS INTEGER) AS DaysSincePost,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
        COALESCE(COUNT(DISTINCT ph.Id), 0) AS HistoryEvents,
        CASE 
            WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts pa WHERE pa.Id = p.ParentId AND pa.AcceptedAnswerId = p.Id) THEN 'AcceptedAnswer'
            WHEN p.PostTypeId = 2 THEN 'RegularAnswer'
            WHEN p.PostTypeId = 1 THEN 'Question'
            ELSE 'Other'
        END AS PostTypeStatus,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.Date > p.CreationDate) AS BadgesAfterPost
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate > TIMESTAMP '2020-01-01'
    GROUP BY p.Id, p.Title, p.Body, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, p.PostTypeId
)
SELECT 
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.PositiveScore,
    ups.AvgScore,
    ups.LastPostDate,
    ups.AllTags,
    tp.TagName,
    tp.Count AS TagCount,
    tp.AvgViews,
    tp.AvgScore AS TagAvgScore,
    tp.TagRank,
    tp.TagCategory,
    tp.RankDrop,
    ua.TotalVotes,
    ua.PostsVotedOn,
    ua.UpVotes,
    ua.DownVotes,
    ua.PercentageOfAllVotes,
    ua.ActivityRank,
    ua.ActivityLevel,
    cpa.Id AS PostId,
    cpa.Title,
    cpa.BodyLength,
    cpa.VoteCategory,
    cpa.TitleLengthCategory,
    cpa.DaysSincePost,
    cpa.CommentCount,
    cpa.HistoryEvents,
    cpa.PostTypeStatus,
    cpa.BadgesAfterPost,
    CASE 
        WHEN cpa.DaysSincePost < 30 THEN 'Hot'
        WHEN cpa.DaysSincePost < 90 THEN 'Warm'
        WHEN cpa.DaysSincePost < 365 THEN 'Cool'
        ELSE 'Cold'
    END AS PostRecency,
    CASE 
        WHEN cpa.Score > 100 THEN 'Legendary'
        WHEN cpa.Score > 50 THEN 'High'
        WHEN cpa.Score > 0 THEN 'Moderate'
        ELSE 'Low'
    END AS PostPopularity,
    CASE 
        WHEN ups.TotalPosts > 100 AND ups.Reputation > 10000 THEN 'Veteran'
        WHEN ups.TotalPosts > 50 AND ups.Reputation > 5000 THEN 'Experienced'
        WHEN ups.TotalPosts > 10 AND ups.Reputation > 1000 THEN 'Active'
        ELSE 'Newbie'
    END AS UserStatus,
    ROW_NUMBER() OVER (PARTITION BY ups.UserId ORDER BY cpa.Score DESC) AS PostRankPerUser,
    (LAG(cpa.Score) OVER (PARTITION BY ups.UserId ORDER BY cpa.Score DESC)) - cpa.Score AS ScoreDifference,
    ROUND( (CAST(cpa.ViewCount AS NUMERIC) / NULLIF(cpa.Score, 0)) , 2) AS ViewsPerScore,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ups.UserId AND p2.CreationDate > TIMESTAMP '2023-01-01') AS RecentPosts2023,
    (SELECT COUNT(DISTINCT v2.PostId) FROM Votes v2 WHERE v2.UserId = ups.UserId AND v2.VoteTypeId = 2 AND v2.CreationDate > TIMESTAMP '2023-01-01') AS RecentUpvotes2023
FROM UserPostStats ups
LEFT JOIN TagPerformance tp ON 1=1
LEFT JOIN UserActivity ua ON ups.UserId = ua.Id
LEFT JOIN ComplexPostAnalysis cpa ON ups.UserId = cpa.OwnerUserId
WHERE (ups.UserId IS NOT NULL OR tp.TagName IS NOT NULL OR ua.Id IS NOT NULL OR cpa.Id IS NOT NULL)
  AND (tp.TagCategory NOT IN ('Tiny', 'Niche') OR tp.TagName IS NULL)
ORDER BY 
    ups.Reputation DESC NULLS LAST,
    tp.Count DESC NULLS LAST,
    ua.TotalVotes DESC NULLS LAST,
    cpa.Score DESC NULLS LAST
FETCH FIRST 10000 ROWS ONLY;