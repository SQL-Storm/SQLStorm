-- {"query": "4610.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1065}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        u.DisplayName AS OwnerDisplayName,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 10
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
),
TopUsersByActivity AS (
    SELECT
        upa.OwnerUserId,
        upa.TotalPostsOwned,
        upa.QuestionCount,
        upa.AnswerCount,
        upa.AvgScore,
        upa.LastPostActivityDate,
        DENSE_RANK() OVER (ORDER BY upa.TotalPostsOwned DESC, upa.AnswerCount DESC) AS ActivityRank
    FROM UserPostActivity upa
    WHERE upa.TotalPostsOwned > 100
),
PostCommentAggregates AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCount,
        SUM(c.Score) AS TotalCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        STRING_AGG(SUBSTRING(c.Text, 1, 30) || '...', '; ') AS SampleComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.PostId
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVoteCount,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS FavoriteVoteCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE vt.Name IN ('UpMod', 'DownMod', 'Favorite')
    GROUP BY v.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.OwnerDisplayName,
    COALESCE(pca.CommentCount, 0) AS ActualCommentCount,
    COALESCE(pca.TotalCommentScore, 0) AS TotalCommentScore,
    pca.LastCommentDate,
    pvs.UpVoteCount,
    pvs.DownVoteCount,
    pvs.FavoriteVoteCount,
    tua.ActivityRank AS OwnerActivityRank,
    tua.TotalPostsOwned AS OwnerTotalPosts,
    CASE
        WHEN rp.PostCreationDate < (CAST('2024-10-01' AS date) - INTERVAL '365' DAY) AND rp.PostTypeName = 'Question' THEN 'Old Question'
        WHEN rp.PostTypeName = 'Answer' AND COALESCE(pvs.UpVoteCount, 0) > COALESCE(pvs.DownVoteCount, 0) * 2 THEN 'Popular Answer'
        ELSE 'Standard Post'
    END AS PostCategorization,
    CASE
        WHEN pca.SampleComments IS NULL THEN 'No Sample Comments Available'
        ELSE pca.SampleComments
    END AS CommentPreview,
    'User ' || COALESCE(CAST(tua.OwnerUserId AS varchar), '') || ' has an activity rank of ' || COALESCE(CAST(tua.ActivityRank AS varchar), '') AS UserActivityInfo
FROM RankedPosts rp
LEFT JOIN PostCommentAggregates pca ON rp.PostId = pca.PostId
LEFT JOIN PostVoteSummary pvs ON rp.PostId = pvs.PostId
LEFT JOIN TopUsersByActivity tua ON rp.OwnerUserId = tua.OwnerUserId
WHERE rp.rn <= 100
  AND (tua.ActivityRank <= 50 OR tua.OwnerUserId IS NULL)
  AND COALESCE(pvs.UpVoteCount, 0) + COALESCE(pvs.DownVoteCount, 0) > 10
GROUP BY
    rp.PostId,
    rp.Title,
    rp.PostTypeName,
    rp.PostCreationDate,
    rp.OwnerDisplayName,
    rp.OwnerUserId,
    pca.CommentCount,
    pca.TotalCommentScore,
    pca.LastCommentDate,
    pca.SampleComments,
    pvs.UpVoteCount,
    pvs.DownVoteCount,
    pvs.FavoriteVoteCount,
    tua.ActivityRank,
    tua.TotalPostsOwned,
    tua.OwnerUserId
ORDER BY rp.PostCreationDate DESC;