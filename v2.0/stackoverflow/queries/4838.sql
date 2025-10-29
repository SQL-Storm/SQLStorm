WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn_user_edit,
        LAG(ph.CreationDate, 1, TIMESTAMP '1900-01-01 00:00:00') OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate) as prev_edit_date_for_user
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserEditFrequency AS (
    SELECT
        UserId,
        COUNT(DISTINCT PostId) AS distinct_posts_edited,
        AVG(EXTRACT(EPOCH FROM (CreationDate - prev_edit_date_for_user)) / 86400.0) AS avg_time_between_edits_days
    FROM RankedPostEdits
    WHERE rn_user_edit = 1
    GROUP BY UserId
    HAVING COUNT(DISTINCT PostId) > 5
       AND AVG(EXTRACT(EPOCH FROM (CreationDate - prev_edit_date_for_user)) / 86400.0) < 30
),
FrequentEditors AS (
    SELECT DISTINCT UserId FROM UserEditFrequency
),
PostDetails AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.AnswerCount,
        p.CommentCount,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        pt.Name AS PostTypeName,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        p.ClosedDate,
        p.CommunityOwnedDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2)
),
CommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
        AVG(c.Score) AS AverageCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
VoteAggregates AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(v.Id) AS TotalVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
UserPostInteraction AS (
    SELECT
        pd.PostId,
        pd.PostTypeName,
        pd.Title,
        pd.OwnerUserId,
        pd.PostCreationDate,
        pd.LastActivityDate,
        pd.Score,
        pd.ViewCount,
        pd.FavoriteCount,
        COALESCE(ca.TotalComments, 0) AS TotalComments,
        COALESCE(ca.PositiveScoreComments, 0) AS PositiveScoreComments,
        COALESCE(ca.AverageCommentScore, 0.0) AS AverageCommentScore,
        COALESCE(va.UpVotes, 0) AS UpVotes,
        COALESCE(va.DownVotes, 0) AS DownVotes,
        pd.PostStatus,
        pd.HasAcceptedAnswer,
        f.UserId AS FrequentEditorUserId,
        SUBSTRING(pd.Title FROM 1 FOR 50) AS ShortTitle,
        UPPER(REPLACE(pd.PostTypeName, ' ', '_')) AS NormalizedPostType
    FROM PostDetails pd
    LEFT JOIN CommentAggregates ca ON pd.PostId = ca.PostId
    LEFT JOIN VoteAggregates va ON pd.PostId = va.PostId
    LEFT JOIN FrequentEditors f ON pd.OwnerUserId = f.UserId
)
SELECT
    upi.PostId,
    upi.NormalizedPostType,
    upi.Title,
    upi.ShortTitle,
    upi.Score,
    upi.ViewCount,
    upi.FavoriteCount,
    upi.TotalComments,
    upi.PositiveScoreComments,
    upi.AverageCommentScore,
    upi.UpVotes,
    upi.DownVotes,
    upi.PostStatus,
    upi.HasAcceptedAnswer,
    (upi.UpVotes - upi.DownVotes) AS NetVotes,
    CASE
        WHEN upi.AverageCommentScore > 3 THEN 'High Activity'
        WHEN upi.TotalComments > 10 THEN 'Engaged'
        ELSE 'Standard'
    END AS InteractionLevel,
    CASE WHEN upi.FrequentEditorUserId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsFrequentEditor,
    EXTRACT(DAY FROM (upi.LastActivityDate - upi.PostCreationDate)) AS PostLifespanDays,
    upi.PostCreationDate,
    upi.LastActivityDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    u.Views AS OwnerViews,
    u.UpVotes AS OwnerUpVotes,
    u.DownVotes AS OwnerDownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS OwnerGoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS OwnerSilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS OwnerBronzeBadges,
    COALESCE(CAST(upi.UpVotes AS DOUBLE PRECISION) / NULLIF(upi.TotalComments, 0), 0.0) AS UpvoteToCommentRatio
FROM UserPostInteraction upi
LEFT JOIN Users u ON upi.OwnerUserId = u.Id
WHERE upi.Score > 100 OR upi.ViewCount > 10000

UNION

SELECT
    pd.Id,
    UPPER(REPLACE(pt.Name, ' ', '_')) AS NormalizedPostType,
    pd.Title,
    SUBSTRING(pd.Title FROM 1 FOR 50) AS ShortTitle,
    pd.Score,
    pd.ViewCount,
    pd.FavoriteCount,
    COALESCE(ca.TotalComments, 0) AS TotalComments,
    COALESCE(ca.PositiveScoreComments, 0) AS PositiveScoreComments,
    COALESCE(ca.AverageCommentScore, 0.0) AS AverageCommentScore,
    COALESCE(va.UpVotes, 0) AS UpVotes,
    COALESCE(va.DownVotes, 0) AS DownVotes,
    CASE
        WHEN pd.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN pd.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Active'
    END AS PostStatus,
    CASE WHEN pd.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
    (COALESCE(va.UpVotes, 0) - COALESCE(va.DownVotes, 0)) AS NetVotes,
    CASE
        WHEN COALESCE(ca.AverageCommentScore, 0.0) > 3 THEN 'High Activity'
        WHEN COALESCE(ca.TotalComments, 0) > 10 THEN 'Engaged'
        ELSE 'Standard'
    END AS InteractionLevel,
    CASE WHEN f.UserId IS NOT NULL THEN 'Yes' ELSE 'No' END AS IsFrequentEditor,
    EXTRACT(DAY FROM (pd.LastActivityDate - pd.CreationDate)) AS PostLifespanDays,
    pd.CreationDate,
    pd.LastActivityDate,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS OwnerGoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS OwnerSilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS OwnerBronzeBadges,
    COALESCE(CAST(COALESCE(va.UpVotes, 0) AS DOUBLE PRECISION) / NULLIF(COALESCE(ca.TotalComments, 0), 0), 0.0) AS UpvoteToCommentRatio
FROM Posts pd
JOIN PostTypes pt ON pd.PostTypeId = pt.Id
LEFT JOIN CommentAggregates ca ON pd.Id = ca.PostId
LEFT JOIN VoteAggregates va ON pd.Id = va.PostId
LEFT JOIN FrequentEditors f ON pd.OwnerUserId = f.UserId
LEFT JOIN Users u ON pd.OwnerUserId = u.Id
WHERE pt.Name = 'Question' AND pd.AnswerCount > 5 AND pd.CreationDate < TIMESTAMP '2023-01-01 00:00:00'
ORDER BY Score DESC
LIMIT 100;