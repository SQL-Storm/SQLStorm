WITH PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount AS PostViewCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 5 THEN 'TagWiki'
            ELSE 'Other'
        END AS PostType,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COUNT(DISTINCT c.Id) AS CommentCountOnPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY ph.CreationDate DESC) AS LatestRevisionRank
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.PostTypeId IN (1, 2, 5)
    GROUP BY
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount,
        u.DisplayName,
        u.Reputation,
        ph.CreationDate
),
UserActivitySummary AS (
    SELECT
        pi.OwnerUserId,
        COUNT(DISTINCT pi.PostId) AS TotalPostsOwned,
        AVG(pi.PostScore) AS AveragePostScore,
        SUM(pi.PostViewCount) AS TotalViewsOnPosts,
        MAX(pi.OwnerReputation) AS MaxOwnerReputation,
        AVG(pi.OwnerReputation) AS AverageOwnerReputation,
        COUNT(DISTINCT CASE WHEN pi.PostTypeId = 1 THEN pi.PostId END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN pi.PostTypeId = 2 THEN pi.PostId END) AS AnswerCount,
        COUNT(DISTINCT CASE WHEN pi.PostTypeId = 5 THEN pi.PostId END) AS TagWikiCount,
        SUM(pi.UpVoteCount) AS TotalUpVotesReceived,
        SUM(pi.DownVoteCount) AS TotalDownVotesReceived,
        CAST(AVG(CAST(pi.PostScore AS NUMERIC)) AS DECIMAL(10, 2)) AS AvgScoreWithPrecision
    FROM PostInteraction pi
    WHERE pi.OwnerUserId IS NOT NULL
    GROUP BY pi.OwnerUserId
),
RankedPostInteractions AS (
    SELECT
        pi.PostId,
        pi.OwnerUserId,
        pi.PostTypeId,
        pi.PostCreationDate,
        pi.PostScore,
        pi.AnswerCount,
        pi.CommentCount,
        pi.FavoriteCount,
        pi.PostViewCount,
        pi.PostType,
        pi.OwnerDisplayName,
        pi.OwnerReputation,
        pi.CommentCountOnPost,
        pi.UpVoteCount,
        pi.DownVoteCount,
        pi.LatestRevisionRank,
        RANK() OVER (ORDER BY pi.PostScore DESC, pi.PostCreationDate ASC) AS ScoreRank,
        LAG(pi.PostScore, 1, 0) OVER (PARTITION BY pi.OwnerUserId ORDER BY pi.PostCreationDate) AS PreviousPostScore
    FROM PostInteraction pi
    WHERE pi.LatestRevisionRank = 1
),
TagWikiCounts AS (
    SELECT
        t.TagName,
        COUNT(DISTINCT p.Id) AS NumberOfTagWikis
    FROM Tags t
    JOIN Posts p ON t.WikiPostId = p.Id AND p.PostTypeId = 5
    GROUP BY t.TagName
),
PostTagsExpanded AS (
    SELECT
        p.Id,
        TRIM(tag) AS TagName
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags) - 2), '><')) AS tag
    ) AS unnested_tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
UserTagPreference AS (
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(*) AS TagUsageCount
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    JOIN PostTagsExpanded PostTags ON p.Id = PostTags.Id
    JOIN Tags t ON PostTags.TagName = t.TagName
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, t.TagName
),
UserPreferredTag AS (
    SELECT
        UserId,
        TagName,
        ROW_NUMBER() OVER (PARTITION BY UserId ORDER BY TagUsageCount DESC, TagName ASC) AS TagRank
    FROM UserTagPreference
)
SELECT
    rpi.PostId,
    rpi.PostType,
    rpi.PostCreationDate,
    rpi.PostScore,
    rpi.PostViewCount,
    rpi.CommentCountOnPost,
    rpi.UpVoteCount,
    rpi.DownVoteCount,
    COALESCE(uas.TotalPostsOwned, 0) AS UserTotalPostsOwned,
    COALESCE(uas.AveragePostScore, 0.0) AS UserAveragePostScore,
    COALESCE(uas.TotalViewsOnPosts, 0) AS UserTotalViewsOnPosts,
    COALESCE(uas.AverageOwnerReputation, 0.0) AS UserAverageOwnerReputation,
    uas.TotalUpVotesReceived AS UserTotalUpVotesReceived,
    uas.TotalDownVotesReceived AS UserTotalDownVotesReceived,
    rpi.ScoreRank,
    rpi.PreviousPostScore,
    twc.NumberOfTagWikis AS RelevantTagWikiCount,
    upt.TagName AS MostFrequentTag,
    CASE
        WHEN rpi.PostScore > COALESCE(uas.AveragePostScore, 0) * 1.5 THEN 'Above Average Score'
        WHEN rpi.PostScore < COALESCE(uas.AveragePostScore, 0) * 0.5 THEN 'Below Average Score'
        ELSE 'Average Score'
    END AS ScorePerformanceCategory,
    CASE
        WHEN rpi.PostViewCount > (SELECT AVG(pi2.PostViewCount) FROM PostInteraction pi2 WHERE pi2.PostTypeId = rpi.PostTypeId) THEN 'High View Count'
        ELSE 'Normal View Count'
    END AS ViewCountCategory,
    CAST(rpi.PostScore AS VARCHAR) || '-' || CAST(rpi.PostViewCount AS VARCHAR) AS ScoreViewComposite,
    (rpi.UpVoteCount + rpi.DownVoteCount) AS TotalVotesCast,
    CASE
        WHEN rpi.OwnerUserId IS NULL THEN 'Community'
        ELSE COALESCE(rpi.OwnerDisplayName, 'Unknown User')
    END AS EffectiveOwnerName,
    COALESCE(rpi.OwnerReputation, 0) AS EffectiveOwnerReputation,
    CASE WHEN rpi.PostScore > 100 AND rpi.AnswerCount > 5 AND rpi.CommentCountOnPost > 10 THEN 'High Engagement Post' ELSE 'Standard Post' END AS EngagementLevel,
    CASE WHEN rpi.PostCreationDate < TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 year' THEN 'Old' ELSE 'New' END AS AgeCategory,
    CASE WHEN rpi.PostScore > 0 AND rpi.PostViewCount > 0 THEN CAST(rpi.PostScore AS NUMERIC) / rpi.PostViewCount ELSE 0 END AS ScoreToViewRatio,
    CASE WHEN rpi.PostScore IS NULL OR rpi.PostScore = 0 THEN TRUE ELSE FALSE END AS IsZeroOrNullScore,
    CASE WHEN rpi.PostCreationDate BETWEEN (CAST('2024-10-01 12:34:56' AS DATE) - INTERVAL '7 day') AND CAST('2024-10-01 12:34:56' AS DATE) THEN 'Last Week' ELSE 'Older' END AS RecentActivityFlag,
    CASE WHEN rpi.PostViewCount > 10000 AND rpi.PostScore > 50 THEN 'Popular High-Scoring' ELSE 'Other' END AS PopularityMetric
FROM RankedPostInteractions rpi
LEFT JOIN UserActivitySummary uas ON rpi.OwnerUserId = uas.OwnerUserId
LEFT JOIN TagWikiCounts twc ON twc.TagName = (
    SELECT t2.TagName FROM Tags t2 WHERE t2.WikiPostId = rpi.PostId LIMIT 1
)
LEFT JOIN UserPreferredTag upt ON rpi.OwnerUserId = upt.UserId AND upt.TagRank = 1
WHERE rpi.PostTypeId IN (1, 2) AND rpi.OwnerUserId IS NOT NULL
ORDER BY rpi.PostScore DESC, rpi.PostCreationDate ASC
LIMIT 100;