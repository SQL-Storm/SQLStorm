-- {"query": "4473.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1856}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn_score_view,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousScore,
        LEAD(p.ViewCount, 1, 0) OVER (ORDER BY p.CreationDate DESC) AS NextViewCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0 AND p.CreationDate > TIMESTAMP '2023-01-01'
),
PostHistoryStats AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 2 THEN 1 END) AS BodyEdits,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 7) THEN 1 END) AS TitleEdits,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastCloseDate,
        COUNT(DISTINCT ph.UserId) AS DistinctEditors
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (2, 4, 7, 10) AND ph.CreationDate > TIMESTAMP '2023-01-01'
    GROUP BY ph.PostId
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS UserPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS UserQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS UserAnswers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCasted,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCasted,
        COUNT(DISTINCT b.Id) AS BadgesEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.CreationDate > TIMESTAMP '2023-01-01'
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.CreationDate > TIMESTAMP '2023-01-01'
    LEFT JOIN Badges b ON u.Id = b.UserId AND b.Date > TIMESTAMP '2023-01-01'
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostPerformance AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerDisplayName,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.rn_score_view,
        rp.PreviousScore,
        rp.NextViewCount,
        phs.BodyEdits,
        phs.TitleEdits,
        phs.LastCloseDate,
        COALESCE(ue.Reputation, 0) AS OwnerReputation,
        COALESCE(ue.UserPosts, 0) AS OwnerTotalPosts,
        COALESCE(ue.UserAnswers, 0) AS OwnerAnswerCount,
        ue.BadgesEarned AS OwnerBadges,
        CASE WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Owned' ELSE 'User Owned' END AS OwnershipStatus,
        CASE WHEN (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - rp.PostCreationDate) > INTERVAL '365 days' THEN 'Old' ELSE 'Recent' END AS AgeCategory,
        (rp.Score * 1.0 / NULLIF(rp.ViewCount, 0)) AS ScoreToViewRatio,
        rp.PostCreationDate,
        rp.OwnerUserId
    FROM RankedPosts rp
    LEFT JOIN PostHistoryStats phs ON rp.PostId = phs.PostId
    LEFT JOIN UserEngagement ue ON rp.OwnerUserId = ue.UserId
    WHERE rp.PostTypeName IS NOT NULL AND rp.OwnerDisplayName IS NOT NULL
)
SELECT
    pp.PostId,
    pp.PostTypeName,
    pp.OwnerDisplayName,
    pp.Score,
    pp.ViewCount,
    pp.AnswerCount,
    pp.CommentCount,
    pp.FavoriteCount,
    pp.rn_score_view,
    pp.PreviousScore,
    pp.NextViewCount,
    pp.BodyEdits,
    pp.TitleEdits,
    pp.LastCloseDate,
    pp.OwnerReputation,
    pp.OwnerTotalPosts,
    pp.OwnerAnswerCount,
    pp.OwnerBadges,
    pp.OwnershipStatus,
    pp.AgeCategory,
    pp.ScoreToViewRatio,
    pp.PostCreationDate,
    CASE
        WHEN pp.Score > 100 AND pp.AnswerCount > 10 THEN 'Highly Rated Question'
        WHEN pp.Score < 0 AND pp.AnswerCount = 0 THEN 'Negatively Scored Question'
        WHEN pp.ViewCount > 10000 AND pp.FavoriteCount > 50 THEN 'Popular Question'
        WHEN COALESCE(pp.BodyEdits, 0) > 5 AND COALESCE(pp.TitleEdits, 0) > 2 THEN 'Frequently Edited Post'
        WHEN pp.OwnerReputation > 100000 AND COALESCE(pp.OwnerBadges, 0) > 20 THEN 'Expert User Post'
        ELSE 'Standard Post'
    END AS PerformanceCategory,
    LOWER(SUBSTRING(pp.OwnerDisplayName FROM 1 FOR 3)) AS OwnerNamePrefix,
    CASE
        WHEN pp.PostCreationDate BETWEEN (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days') AND CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) THEN 'Last Week'
        WHEN pp.PostCreationDate BETWEEN (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '28 days') AND (CAST(TIMESTAMP '2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '7 days') THEN 'Last Month'
        ELSE 'Older'
    END AS PostAgeGroup,
    pp.OwnerUserId
FROM PostPerformance pp
WHERE pp.ScoreToViewRatio IS NOT NULL AND pp.OwnerReputation > 500
UNION ALL
SELECT
    CAST(NULL AS BIGINT) AS PostId,
    'Summary' AS PostTypeName,
    'Overall Performance Metrics' AS OwnerDisplayName,
    SUM(Score) AS Score,
    SUM(ViewCount) AS ViewCount,
    SUM(AnswerCount) AS AnswerCount,
    SUM(CommentCount) AS CommentCount,
    SUM(FavoriteCount) AS FavoriteCount,
    AVG(rn_score_view) AS rn_score_view,
    AVG(PreviousScore) AS PreviousScore,
    AVG(NextViewCount) AS NextViewCount,
    SUM(BodyEdits) AS BodyEdits,
    SUM(TitleEdits) AS TitleEdits,
    CAST(NULL AS TIMESTAMP) AS LastCloseDate,
    AVG(OwnerReputation) AS OwnerReputation,
    SUM(OwnerTotalPosts) AS OwnerTotalPosts,
    SUM(OwnerAnswerCount) AS OwnerAnswerCount,
    AVG(OwnerBadges) AS OwnerBadges,
    CAST(NULL AS TEXT) AS OwnershipStatus,
    CAST(NULL AS TEXT) AS AgeCategory,
    AVG(ScoreToViewRatio) AS ScoreToViewRatio,
    CAST(NULL AS TIMESTAMP) AS PostCreationDate,
    CAST(NULL AS TEXT) AS PerformanceCategory,
    CAST(NULL AS TEXT) AS OwnerNamePrefix,
    CAST(NULL AS TEXT) AS PostAgeGroup,
    CAST(NULL AS BIGINT) AS OwnerUserId
FROM PostPerformance pp
WHERE pp.ScoreToViewRatio IS NOT NULL AND pp.OwnerReputation > 500;