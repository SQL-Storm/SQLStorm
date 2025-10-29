-- {"query": "4467.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1257} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        pht.Name AS LastEditType,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC) as rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE p.PostTypeId IN (1, 2) AND p.Score > 0 AND p.CreationDate > '2023-01-01'
),
PostAggregates AS (
    SELECT
        rp.PostId,
        rp.PostTypeName,
        rp.OwnerUserId,
        rp.OwnerDisplayName,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.AnswerCount,
        rp.CommentCount,
        rp.FavoriteCount,
        rp.ClosedDate,
        rp.LastEditType,
        AVG(rp.Score) OVER(PARTITION BY rp.OwnerUserId) AS AvgUserScore,
        SUM(rp.ViewCount) OVER(PARTITION BY rp.OwnerUserId) AS TotalUserViews,
        COUNT(rp.PostId) OVER(PARTITION BY rp.OwnerUserId) AS UserPostCount,
        CASE WHEN rp.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN rp.OwnerUserId IS NULL THEN 'Community' ELSE rp.OwnerDisplayName END AS DisplayOwnerName
    FROM RankedPosts rp
    WHERE rp.rn = 1
),
CommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS CommentCountPerPost,
        SUM(c.Score) AS TotalCommentScore,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate,
        COUNT(CASE WHEN c.UserId IS NULL THEN 1 END) AS AnonymousComments
    FROM Comments c
    GROUP BY c.PostId
),
VoteAnalysis AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
        COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
        COUNT(CASE WHEN vt.Name = 'Favorite' THEN 1 END) AS Favorites,
        COUNT(CASE WHEN vt.Name = 'AcceptedByOriginator' THEN 1 END) AS AcceptedVotes
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
DuplicateLinks AS (
    SELECT
        pl.PostId,
        COUNT(pl.Id) AS DuplicateLinkCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE lt.Name = 'Duplicate'
    GROUP BY pl.PostId
),
CombinedData AS (
    SELECT
        pa.*,
        ca.CommentCountPerPost,
        ca.TotalCommentScore,
        ca.AvgCommentScore,
        ca.LastCommentDate,
        ca.AnonymousComments,
        va.UpVotes,
        va.DownVotes,
        va.Favorites,
        va.AcceptedVotes,
        dl.DuplicateLinkCount
    FROM PostAggregates pa
    LEFT JOIN CommentAnalysis ca ON pa.PostId = ca.PostId
    LEFT JOIN VoteAnalysis va ON pa.PostId = va.PostId
    LEFT JOIN DuplicateLinks dl ON pa.PostId = dl.PostId
)
SELECT
    cd.PostId,
    cd.PostTypeName,
    cd.DisplayOwnerName,
    cd.CreationDate,
    cd.Score,
    cd.ViewCount,
    cd.AnswerCount,
    cd.CommentCount,
    cd.FavoriteCount,
    cd.ClosedDate,
    cd.LastEditType,
    cd.AvgUserScore,
    cd.TotalUserViews,
    cd.UserPostCount,
    cd.IsClosed,
    COALESCE(cd.CommentCountPerPost, 0) AS EffectiveCommentCount,
    COALESCE(cd.TotalCommentScore, 0) AS TotalCommentScore,
    COALESCE(cd.AvgCommentScore, 0) AS AvgCommentScore,
    cd.LastCommentDate,
    COALESCE(cd.AnonymousComments, 0) AS AnonymousComments,
    COALESCE(cd.UpVotes, 0) AS TotalUpVotes,
    COALESCE(cd.DownVotes, 0) AS TotalDownVotes,
    COALESCE(cd.Favorites, 0) AS TotalFavorites,
    COALESCE(cd.AcceptedVotes, 0) AS AcceptedVotesCount,
    COALESCE(cd.DuplicateLinkCount, 0) AS DuplicateLinks
FROM CombinedData cd
WHERE cd.Score > 100
ORDER BY cd.Score DESC, cd.ViewCount DESC
LIMIT 100;
