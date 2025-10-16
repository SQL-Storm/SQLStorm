WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        MAX(c.CreationDate) AS LastCommentActivity,
        MAX(v.CreationDate) AS LastVoteActivity,
        MAX(b.Date) AS LastBadgeActivity,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS ReputationRank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.Reputation
) ,
InfluentialUsers AS (
    SELECT
        UserId,
        Reputation,
        TotalPosts,
        TotalComments,
        TotalVotes,
        TotalBadges,
        LastPostActivity,
        LastCommentActivity,
        LastVoteActivity,
        LastBadgeActivity,
        ReputationRank
    FROM
        UserActivity
    WHERE
        ReputationRank <= 100
) ,
RecentPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostRank
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '6' MONTH)
) ,
TagMetrics AS (
    SELECT
        t.TagName,
        COUNT(rp.PostId) AS PostCount,
        SUM(rp.Score) AS TotalScore,
        SUM(rp.ViewCount) AS TotalViews,
        AVG(rp.AnswerCount) AS AvgAnswerCount,
        STRING_AGG(rp.Title, ', ') AS SampleTitles
    FROM
        Tags t
    JOIN
        RecentPosts rp ON POSITION(t.TagName IN rp.Tags) > 0
    GROUP BY
        t.TagName
),
HistoryUserMetrics AS (
    SELECT
        ph.UserId,
        u.DisplayName,
        ph.PostId,
        COUNT(ph.Id) AS EditCount,
        ph.CreationDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS CloseReason,
        MAX(CASE WHEN ph.PostHistoryTypeId = 1 THEN ph.Text END) AS InitialTitle,
        MAX(CASE WHEN ph.PostHistoryTypeId = 14 THEN ph.CreationDate END) AS LockedDate,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (2,5) THEN LENGTH(ph.Text) END) AS TotalEditLength
    FROM
        PostHistory ph
    JOIN
        Users u ON ph.UserId = u.Id
    WHERE
        ph.PostHistoryTypeId IN (1, 2, 5, 10, 14)
    GROUP BY
        ph.UserId, u.DisplayName, ph.PostId, ph.CreationDate
)
SELECT
    iu.UserId,
    iu.Reputation,
    iu.TotalPosts,
    iu.TotalComments,
    iu.TotalVotes,
    iu.TotalBadges,
    iu.LastPostActivity,
    iu.LastCommentActivity,
    iu.LastVoteActivity,
    iu.LastBadgeActivity,
    rp.PostId,
    rp.PostTypeId,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Title,
    rp.Tags,
    rp.AnswerCount,
    tm.TagName,
    tm.PostCount,
    tm.TotalScore,
    tm.TotalViews,
    tm.AvgAnswerCount,
    tm.SampleTitles,
    hum.EditCount,
    hum.CloseReason,
    hum.InitialTitle,
    hum.LockedDate,
    hum.TotalEditLength
FROM
    InfluentialUsers iu
JOIN
    RecentPosts rp ON iu.UserId = rp.OwnerUserId
JOIN
    TagMetrics tm ON POSITION(tm.TagName IN rp.Tags) > 0
LEFT JOIN
    HistoryUserMetrics hum ON iu.UserId = hum.UserId AND rp.PostId = hum.PostId
WHERE
    rp.PostRank = 1
ORDER BY
    iu.Reputation DESC,
    rp.CreationDate DESC;