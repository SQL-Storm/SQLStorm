-- {"query": "49017.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 1835} 

WITH HotTags AS (
    -- Identify popular and well-defined tags based on count and wiki presence
    SELECT
        t.TagName,
        t.Id AS TagId
    FROM Tags t
    WHERE t.Count > 50000 -- Filter for sufficiently popular tags
      AND t.WikiPostId IS NOT NULL -- Ensure a tag wiki exists, indicating established tags
    ORDER BY t.Count DESC
    LIMIT 100 -- Focus on the top 100 most active tags for performance
),
PostTagsExpanded AS (
    -- Explode tags for each post into individual rows and join with HotTags
    -- This de-normalizes tags for efficient filtering and aggregation
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.CreationDate,
        p.AcceptedAnswerId,
        ht.TagName -- The specific hot tag this post belongs to
    FROM Posts p
    JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS PostTagName ON TRUE
    JOIN HotTags ht ON PostTagName = ht.TagName
    WHERE p.Tags IS NOT NULL AND p.Tags != '' AND p.OwnerUserId IS NOT NULL -- Exclude posts without tags or owner
      AND p.CreationDate >= '2020-01-01' -- Focus on recent post activity for relevance
),
UserActivityByTag AS (
    -- Aggregate user post activity within each hot tag, including accepted answers
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        pte.TagName,
        COUNT(DISTINCT pte.PostId) AS TotalPostsInTag,
        SUM(pte.Score) AS TotalPostScoreInTag,
        SUM(CASE WHEN pte.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsInTag,
        SUM(CASE WHEN pte.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersInTag,
        -- Count how many of this user's posts (which must be answers) were accepted for any question
        COUNT(DISTINCT q.Id) FILTER (WHERE q.AcceptedAnswerId = pte.PostId AND pte.PostTypeId = 2) AS AcceptedAnswersInTag
    FROM Users u
    JOIN PostTagsExpanded pte ON u.Id = pte.OwnerUserId
    LEFT JOIN Posts q ON pte.PostId = q.AcceptedAnswerId AND q.PostTypeId = 1 -- Join to find questions that accepted this post as an answer
    WHERE pte.PostTypeId IN (1, 2) -- Only consider questions and answers for tag activity
    GROUP BY u.Id, u.DisplayName, u.Reputation, pte.TagName
    HAVING COUNT(DISTINCT pte.PostId) >= 5 -- Users must have at least 5 posts in the tag
),
UserOverallStats AS (
    -- Compute comprehensive overall statistics for each user
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(p.Score) AS TotalPostScore,
        SUM(p.ViewCount) AS TotalPostViews,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore,
        COUNT(DISTINCT ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS TotalEdits, -- Count only specific post edit history types
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2 AND v.UserId = u.Id) AS TotalUpVotesGiven, -- Upvotes cast by the user
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3 AND v.UserId = u.Id) AS TotalDownVotesGiven, -- Downvotes cast by the user
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 1000 -- Filter for users with significant reputation
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
RankedContributors AS (
    -- Calculate a composite contribution score and rank users based on various metrics
    SELECT
        uos.UserId,
        uos.DisplayName,
        uos.Reputation,
        uos.TotalPosts,
        uos.TotalPostScore,
        uos.TotalComments,
        uos.TotalEdits,
        uos.GoldBadges,
        uos.SilverBadges,
        uos.BronzeBadges,
        -- Weighted sum combining post score, edits, badges, and comments
        (uos.TotalPostScore * 0.5) +
        (uos.TotalEdits * 0.1) +
        (uos.GoldBadges * 100) +
        (uos.SilverBadges * 20) +
        (uos.BronzeBadges * 5) +
        (uos.TotalComments * 0.05) AS CompositeContributionScore,
        -- Rank users based on reputation, post score, and edits
        RANK() OVER (ORDER BY uos.Reputation DESC, uos.TotalPostScore DESC, uos.TotalEdits DESC) AS OverallRank,
        -- Assign users to deciles based on their reputation
        NTILE(10) OVER (ORDER BY uos.Reputation DESC) AS ReputationDecile
    FROM UserOverallStats uos
    WHERE uos.TotalPosts > 10 OR uos.TotalEdits > 5 OR uos.GoldBadges > 0 -- Filter for active contributors
),
TopTagContributors AS (
    -- For each hot tag, identify the top contributor based on post score and accepted answers
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.TagName,
        ua.TotalPostsInTag,
        ua.TotalPostScoreInTag,
        ua.AcceptedAnswersInTag,
        ROW_NUMBER() OVER (PARTITION BY ua.TagName ORDER BY ua.TotalPostScoreInTag DESC, ua.AcceptedAnswersInTag DESC) AS TagRank
    FROM UserActivityByTag ua
)
-- Final result: Combine overall ranked contributors with their primary hot tag contribution
SELECT
    rc.UserId,
    rc.DisplayName,
    rc.Reputation,
    rc.OverallRank,
    rc.ReputationDecile,
    rc.TotalPosts,
    rc.TotalPostScore,
    rc.TotalComments,
    rc.TotalEdits,
    rc.GoldBadges,
    rc.SilverBadges,
    rc.BronzeBadges,
    rc.CompositeContributionScore,
    ttc.TagName AS TopContributingTag, -- The single tag where the user ranks highest
    ttc.TotalPostsInTag,
    ttc.TotalPostScoreInTag,
    ttc.AcceptedAnswersInTag
FROM RankedContributors rc
LEFT JOIN TopTagContributors ttc ON rc.UserId = ttc.UserId AND ttc.TagRank = 1 -- Join to get the user's highest ranked tag contribution
WHERE rc.OverallRank <= 100 -- Restrict to the top 100 overall contributors for a manageable result set
ORDER BY rc.OverallRank ASC, ttc.TagName ASC;
