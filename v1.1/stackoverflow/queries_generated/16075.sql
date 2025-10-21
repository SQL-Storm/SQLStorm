-- {"query": "16075.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 2132}

WITH RECURSIVE user_influence AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
        EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
        CASE 
            WHEN u.Location IS NULL THEN 'Unknown'
            WHEN LENGTH(TRIM(u.Location)) = 0 THEN 'Not Specified'
            ELSE UPPER(SUBSTRING(u.Location, 1, 50))
        END AS NormalizedLocation
    FROM Users u
    WHERE u.Reputation > 1000
),
post_metrics AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE 
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END AS HasAcceptedAnswer,
        EXTRACT(EPOCH FROM (COALESCE(p.LastActivityDate, p.CreationDate) - p.CreationDate)) / 3600 AS HoursActive,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC NULLS LAST) AS UserPostRank,
        AVG(p.Score) OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate)) AS YearlyAvgScore,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId) AS UserPostTypeCount
    FROM Posts p
    WHERE p.CreationDate >= '2018-01-01'
        AND p.PostTypeId IN (1, 2)
),
tag_expertise AS (
    SELECT 
        p.OwnerUserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) AS Tag,
        COUNT(*) AS TagPostCount,
        AVG(p.Score) AS AvgTagScore,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL OR p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TagAnswerCount
    FROM Posts p
    WHERE p.Tags IS NOT NULL 
        AND p.PostTypeId = 1
        AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'))
    HAVING COUNT(*) >= 3
),
badge_analysis AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldCount,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverCount,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeCount,
        COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBasedCount,
        ARRAY_AGG(DISTINCT b.Name ORDER BY b.Name) FILTER (WHERE b.Class = 1) AS GoldBadges
    FROM Badges b
    GROUP BY b.UserId
),
vote_patterns AS (
    SELECT 
        v.PostId,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownvoteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS FavoriteCount,
        COUNT(*) FILTER (WHERE v.VoteTypeId = 8) AS BountyStartCount,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBountyAmount,
        MAX(v.CreationDate) AS LastVoteDate
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3, 5, 8, 9)
    GROUP BY v.PostId
)
SELECT 
    ui.DisplayName,
    ui.Reputation,
    ui.NormalizedLocation,
    ui.NetVotes,
    ui.JoinYear,
    pm.UserPostTypeCount,
    COALESCE(ba.GoldCount, 0) AS GoldBadges,
    COALESCE(ba.SilverCount, 0) AS SilverBadges,
    COALESCE(ba.BronzeCount, 0) AS BronzeBadges,
    ROUND(AVG(pm.Score)::numeric, 2) AS AvgPostScore,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pm.Score)::numeric, 2) AS MedianPostScore,
    MAX(pm.Score) AS MaxPostScore,
    SUM(COALESCE(pm.ViewCount, 0)) AS TotalViews,
    COUNT(DISTINCT pm.PostId) AS TotalPosts,
    COUNT(DISTINCT te.Tag) AS UniqueTags,
    STRING_AGG(DISTINCT te.Tag, ', ' ORDER BY te.Tag) FILTER (WHERE te.TagPostCount >= 5) AS TopTags,
    ROUND(AVG(vp.UpvoteCount)::numeric, 2) AS AvgUpvotesPerPost,
    ROUND(AVG(vp.DownvoteCount)::numeric, 2) AS AvgDownvotesPerPost,
    SUM(vp.TotalBountyAmount) AS TotalBountiesReceived,
    CASE 
        WHEN SUM(pm.HasAcceptedAnswer) > 0 THEN ROUND((SUM(pm.HasAcceptedAnswer)::numeric / COUNT(*) FILTER (WHERE pm.PostTypeId = 1)) * 100, 2)
        ELSE 0 
    END AS AcceptanceRate,
    ROUND(AVG(pm.HoursActive) FILTER (WHERE pm.HoursActive < 8760)::numeric, 2) AS AvgHoursActive,
    COUNT(*) FILTER (WHERE pm.UserPostRank <= 5) AS Top5Posts,
    (SELECT COUNT(*) 
     FROM Comments c 
     INNER JOIN Posts p2 ON c.PostId = p2.Id 
     WHERE c.UserId = ui.Id AND p2.OwnerUserId != ui.Id) AS CommentsOnOtherPosts,
    (SELECT COUNT(DISTINCT ph.PostId)
     FROM PostHistory ph
     WHERE ph.UserId = ui.Id 
       AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
    DENSE_RANK() OVER (ORDER BY ui.Reputation DESC) AS ReputationRank,
    NTILE(10) OVER (ORDER BY COUNT(DISTINCT pm.PostId) DESC) AS ActivityDecile
FROM user_influence ui
LEFT OUTER JOIN post_metrics pm ON ui.Id = pm.OwnerUserId
LEFT OUTER JOIN tag_expertise te ON ui.Id = te.OwnerUserId AND te.AvgTagScore > 0
LEFT OUTER JOIN badge_analysis ba ON ui.Id = ba.UserId
LEFT OUTER JOIN vote_patterns vp ON pm.PostId = vp.PostId
WHERE EXISTS (
    SELECT 1 
    FROM Posts p3 
    WHERE p3.OwnerUserId = ui.Id 
      AND p3.Score >= (SELECT AVG(Score) FROM Posts WHERE PostTypeId = p3.PostTypeId)
)
GROUP BY ui.Id, ui.DisplayName, ui.Reputation, ui.NormalizedLocation, ui.NetVotes, ui.JoinYear, pm.UserPostTypeCount, ba.GoldCount, ba.SilverCount, ba.BronzeCount
HAVING COUNT(DISTINCT pm.PostId) >= 5
    AND AVG(pm.Score) > 2
    AND COALESCE(SUM(COALESCE(pm.ViewCount, 0)), 0) > 100
ORDER BY 
    ui.Reputation DESC,
    COUNT(DISTINCT pm.PostId) DESC,
    AVG(pm.Score) DESC NULLS LAST
LIMIT 500;
