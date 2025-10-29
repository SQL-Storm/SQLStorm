-- {"query": "4266.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1614} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation AS UserReputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostsEditedCount,
        MAX(ph.CreationDate) AS LastEditDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotesReceived,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3)
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostQuality AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        COALESCE(p.AnswerCount, 0) + COALESCE(p.CommentCount, 0) AS TotalInteractions,
        CASE WHEN p.Score > 10 AND p.AnswerCount >= 3 THEN 'High Quality'
             WHEN p.Score > 0 AND p.AnswerCount >= 1 THEN 'Medium Quality'
             ELSE 'Low Quality'
        END AS QualityRank,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank
    FROM Posts p
    WHERE p.PostTypeId = 1 -- Focus on questions for this metric
),
TagEngagement AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%') AS PostsMentioningTag,
        COALESCE((SELECT SUM(p.Score) FROM Posts p WHERE p.Tags LIKE '%' || t.TagName || '%'), 0) AS TotalScoreForTag,
        CASE WHEN t.IsModeratorOnly = 1 THEN 'Moderator Only' ELSE 'Public' END AS TagAccessLevel,
        CASE WHEN t.IsRequired = 1 THEN 'Required' ELSE 'Optional' END AS TagRequirement
    FROM Tags t
    WHERE t.TagName NOT LIKE '%[^a-z0-9-]%' -- Basic tag name validation
)
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostViewCount,
    ua.UserDisplayName,
    ua.UserReputation,
    ua.UserCreationDate,
    ua.PostsEditedCount,
    ua.LastEditDate,
    ua.TotalUpvotesReceived,
    ua.TotalDownvotesReceived,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    ua.BronzeBadgeCount,
    pq.PostStatus,
    pq.QualityRank,
    pq.ScoreRank,
    te.TagName AS TopTagName,
    te.TagPostCount,
    te.PostsMentioningTag,
    te.TotalScoreForTag,
    te.TagAccessLevel,
    te.TagRequirement,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3) AS DuplicateLinks,
    CASE WHEN rp.PostScore > 50 THEN 'Very Popular'
         WHEN rp.PostViewCount > 10000 THEN 'Highly Viewed'
         ELSE 'Standard'
    END AS PostPopularity,
    UPPER(SUBSTRING(rp.Title, 1, 3)) AS TitlePrefix,
    CASE
        WHEN ua.UserReputation >= 100000 THEN 'Elite'
        WHEN ua.UserReputation >= 50000 THEN 'Veteran'
        WHEN ua.UserReputation >= 10000 THEN 'Experienced'
        WHEN ua.UserReputation >= 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserExperienceLevel,
    CASE
        WHEN rp.PostCreationDate < NOW() - INTERVAL '1 year' AND rp.PostScore < 5 THEN 'Stale Question'
        WHEN rp.PostCreationDate >= NOW() - INTERVAL '1 day' AND rp.PostScore >= 2 THEN 'Recent High Scorer'
        ELSE 'Normal'
    END AS PostAgeAndScoreCombination,
    COALESCE(ua.UserDisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
    CASE WHEN ua.UserReputation IS NULL THEN 0 ELSE ua.UserReputation END AS NonNullReputation,
    CASE WHEN rp.PostTypeName = 'Question' THEN
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = rp.PostId AND c.Score > 0)
    ELSE 0 END AS PositiveCommentsOnQuestion
FROM RankedPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
LEFT JOIN PostQuality pq ON rp.PostId = pq.PostId AND rp.PostTypeId = pq.PostTypeId
LEFT JOIN TagEngagement te ON te.TagName IN (SELECT TagName FROM UNNEST(string_to_array(SUBSTRING(rp.Title FROM '<a href="[^"]*"><b>' FOR '</b></a>'), '><')) AS TagsArray(TagName)) -- Simplified tag extraction for demonstration
WHERE rp.rn <= 100 -- Limit to top 100 posts of each type for performance consideration
AND ua.UserReputation > 1000 -- Filter for users with at least some reputation
ORDER BY rp.PostCreationDate DESC
LIMIT 1000;
