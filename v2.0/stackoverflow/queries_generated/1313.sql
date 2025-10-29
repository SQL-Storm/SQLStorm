-- {"query": "1313.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1319} 
WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.CreationDate AS UserCreationDate,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AvgOverallPostScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1, 2)) AS AvgRelevantPostScore,
        MAX(p.ViewCount) AS MaxPostViewCount,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotesGiven,
        MAX(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS LatestGoldBadgeDate,
        MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS FirstGoldBadgeDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount
    FROM Users AS u
    LEFT JOIN Posts AS p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments AS c ON u.Id = c.UserId
    LEFT JOIN Votes AS v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3) -- UpMod, DownMod
    LEFT JOIN Badges AS b ON u.Id = b.UserId
    GROUP BY u.Id, u.CreationDate, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
UserOverallRank AS (
    SELECT
        uas.UserId,
        uas.Reputation,
        uas.TotalPosts,
        uas.TotalPostScore,
        uas.AvgOverallPostScore,
        uas.UserCreationDate,
        RANK() OVER (ORDER BY uas.Reputation DESC, uas.TotalPostScore DESC) AS GlobalRepRank,
        NTILE(10) OVER (ORDER BY uas.TotalPosts DESC) AS PostVolumeDecile
    FROM UserActivitySummary AS uas
    WHERE uas.TotalPosts > 0
),
UserNeighboringActivity AS (
    SELECT
        uor.UserId,
        uor.GlobalRepRank,
        uor.PostVolumeDecile,
        uor.AvgOverallPostScore,
        AVG(uor.AvgOverallPostScore) OVER (ORDER BY uor.UserCreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS AvgScoreNeighboringUsers
    FROM UserOverallRank AS uor
),
PostTagAnalysis AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount,
        p.Title,
        p.Body,
        p.Tags,
        p.LastEditDate,
        p.LastActivityDate,
        ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'), 1) AS TagCount,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn_latest_post_by_user,
        SUM(p.Score) OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate) AS RunningPostTypeScore,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore
    FROM Posts AS p
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
    AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
),
RecentPostHistoryDetails AS (
    SELECT
        ph.PostId,
        ph.UserId AS HistoryUserId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        ph.Text AS HistoryText,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) AS rn_latest_history_type,
        LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS NextHistoryDate
    FROM PostHistory AS ph
    WHERE ph.PostHistoryTypeId IN (2, 5, 8, 10, 11) -- Initial Body, Edit Body, Rollback Body, Post Closed, Post Reopened
    AND ph.UserId IS NOT NULL
),
HighReputationGoldUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        uas.TotalQuestions,
        uas.TotalAnswers,
        uas.AvgRelevantPostScore,
        uas.GoldBadgesCount,
        uas.FirstGoldBadgeDate,
        pta.PostId AS LatestPostId,
        pta.Title AS LatestPostTitle,