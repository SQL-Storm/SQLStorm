-- {"query": "4049.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1682} 
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount AS PostViewCount,
        COUNT(DISTINCT c.Id) AS CommentCountTotal,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS PostRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        p.ViewCount
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT pe.PostId) AS UserPostCount,
        SUM(pe.PostScore) AS TotalUserPostScore,
        AVG(pe.PostScore) AS AvgUserPostScore,
        MAX(pe.PostCreationDate) AS LatestUserPostDate,
        CASE
            WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 1
            ELSE 0
        END AS HasWebsite,
        CASE
            WHEN u.AboutMe IS NOT NULL AND u.AboutMe <> '' THEN 1
            ELSE 0
        END AS HasAboutMe
    FROM Users u
    LEFT JOIN PostEngagement pe ON u.Id = pe.OwnerUserId
    GROUP BY
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.WebsiteUrl,
        u.AboutMe
),
TagPopularity AS (
    SELECT
        t.TagName,
        t.Count AS TagPostCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    WHERE t.TagName NOT LIKE '%[^a-zA-Z0-9-]%' -- Filter for valid tag names (basic example)
),
PostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 4 THEN ph.CreationDate ELSE NULL END) AS LastTitleEditDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVoteCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenVoteCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 16 THEN ph.UserId ELSE NULL END) AS CommunityOwnedCount
    FROM PostHistory ph
    GROUP BY ph.PostId
)
SELECT
    pe.PostId,
    pt.Name AS PostType,
    ua.DisplayName AS OwnerDisplayName,
    ua.Reputation,
    pe.PostCreationDate,
    pe.PostScore,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.PostViewCount,
    pe.UpVotes,
    pe.DownVotes,
    pe.PostRank,
    pe.PreviousPostScore,
    COALESCE(pha.LastTitleEditDate, pe.PostCreationDate) AS LastSignificantEditDate,
    pha.CloseVoteCount,
    pha.ReopenVoteCount,
    CASE
        WHEN pe.PostScore > 100 AND pe.CommentCount > 5 THEN 'High Engagement'
        WHEN pe.PostScore < 0 AND pe.CommentCount < 2 THEN 'Low Engagement'
        ELSE 'Moderate Engagement'
    END AS EngagementCategory,
    ua.UserPostCount,
    ua.AvgUserPostScore,
    ua.HasWebsite,
    ua.HasAboutMe,
    SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2) AS CleanedTags, -- Basic tag cleaning
    tp.TagRank,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS IsAnswerOrQuestion,
    ua.UserCreationDate,
    (JULIANDAY('now') - JULIANDAY(ua.UserCreationDate)) / 365.25 AS UserAgeInYears,
    pha.CommunityOwnedCount,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY pe.PostScore DESC) AS PostRankByType
FROM PostEngagement pe
JOIN PostTypes pt ON pe.PostTypeId = pt.Id
LEFT JOIN UserActivity ua ON pe.OwnerUserId = ua.UserId
LEFT JOIN Posts p ON pe.PostId = p.Id
LEFT JOIN PostHistoryAnalysis pha ON pe.PostId = pha.PostId
LEFT JOIN TagPopularity tp ON tp.TagName IN (SELECT value FROM json_each('["' || REPLACE(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', '","') || '"]')) -- Assuming tags are stored in a JSON-like array format (adjust if necessary)
WHERE pe.PostScore > -5 -- Filter out heavily downvoted or low-score posts for this analysis
  AND pe.PostCreationDate >= DATE('now', '-365 days') -- Last year
GROUP BY
    pe.PostId,
    pt.Name,
    ua.DisplayName,
    ua.Reputation,
    pe.PostCreationDate,
    pe.PostScore,
    pe.CommentCount,
    pe.FavoriteCount,
    pe.PostViewCount,
    pe.UpVotes,
    pe.DownVotes,
    pe.PostRank,
    pe.PreviousPostScore,
    LastSignificantEditDate,
    pha.CloseVoteCount,
    pha.ReopenVoteCount,
    EngagementCategory,
    ua.UserPostCount,
    ua.AvgUserPostScore,
    ua.HasWebsite,
    ua.HasAboutMe,
    CleanedTags,
    tp.TagRank,
    PostStatus,
    IsAnswerOrQuestion,
    ua.UserCreationDate,
    UserAgeInYears,
    pha.CommunityOwnedCount
ORDER BY pe.PostCreationDate DESC
LIMIT 1000;