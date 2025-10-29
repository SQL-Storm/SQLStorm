WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn_user_post,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate) as prev_edit_date
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6)
),
UserAvgPostScore AS (
    SELECT
        u.Id as UserId,
        AVG(CAST(p.Score AS DECIMAL)) as AvgPostScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.Score IS NOT NULL AND p.Score > 0
    GROUP BY u.Id
),
PostLaggedVotes AS (
    SELECT
        v.PostId,
        v.UserId,
        v.VoteTypeId,
        v.CreationDate,
        LAG(v.CreationDate, 1, v.CreationDate) OVER(PARTITION BY v.PostId, v.VoteTypeId ORDER BY v.CreationDate) as PreviousVoteDate
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostTypeName,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerDisplayName,
    p.Title,
    p.Tags,
    p.CreationDate AS PostCreationDate,
    p.LastActivityDate,
    p.Score AS PostScore,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    UPPER(p.ContentLicense) AS PostContentLicense,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoringCommentCount,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) THEN 'Duplicate Link Exists'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN pht.Name IS NULL THEN 'No History'
        ELSE pht.Name
    END AS LastEditType,
    COALESCE(p.LastEditorDisplayName, 'Community') AS LastEditor,
    EXTRACT(YEAR FROM (p.LastActivityDate - p.CreationDate)) AS AgeInYears,
    CASE
        WHEN LENGTH(p.Body) > 1000 THEN 'Long Body'
        WHEN LENGTH(p.Body) BETWEEN 500 AND 1000 THEN 'Medium Body'
        ELSE 'Short Body'
    END AS BodyLengthCategory,
    COALESCE(uas.AvgPostScore, 0) AS OwnerAvgPostScore,
    plv.VoteTypeId AS LastVoteType,
    plv.CreationDate AS LastVoteDate,
    rpe.CreationDate AS LastEditBySpecificUserDate,
    rpe.Comment AS LastEditComment,
    (p.Id % 10) AS PostIdMod10,
    SUBSTRING(p.Title FROM 1 FOR 10) AS First10CharsOfTitle,
    CASE
        WHEN p.ParentId IS NOT NULL THEN (SELECT pt_parent.Name FROM Posts p_parent JOIN PostTypes pt_parent ON p_parent.PostTypeId = pt_parent.Id WHERE p_parent.Id = p.ParentId)
        ELSE 'N/A'
    END AS ParentPostType,
    CASE
        WHEN p.AcceptedAnswerId IS NOT NULL THEN (SELECT COALESCE(u_answer.DisplayName, p_answer.OwnerDisplayName) FROM Posts p_answer LEFT JOIN Users u_answer ON p_answer.OwnerUserId = u_answer.Id WHERE p_answer.Id = p.AcceptedAnswerId)
        ELSE 'Not Accepted'
    END AS AcceptedAnswerer,
    COALESCE(p.ViewCount, 0) + COALESCE(p.Score, 0) AS ViewScoreSum,
    CASE WHEN p.Tags LIKE '%<sql>%' THEN 1 ELSE 0 END AS HasSqlTag
FROM Posts p
LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostHistory ph_last ON p.Id = ph_last.PostId AND ph_last.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN PostHistoryTypes pht ON ph_last.PostHistoryTypeId = pht.Id
LEFT JOIN UserAvgPostScore uas ON p.OwnerUserId = uas.UserId
LEFT JOIN (
    SELECT PostId, VoteTypeId, CreationDate
    FROM PostLaggedVotes
    WHERE PreviousVoteDate = CreationDate
) plv ON p.Id = plv.PostId
LEFT JOIN (
    SELECT PostId, UserId, CreationDate, Comment
    FROM RankedPostEdits
    WHERE rn_user_post = 1 AND CreationDate > prev_edit_date
) rpe ON p.Id = rpe.PostId AND p.LastEditorUserId = rpe.UserId
WHERE p.CreationDate > DATE '2023-01-01'
GROUP BY
    p.Id,
    pt.Name,
    u.DisplayName,
    p.OwnerDisplayName,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.CommunityOwnedDate,
    p.ContentLicense,
    pht.Name,
    p.LastEditorDisplayName,
    p.OwnerUserId,
    p.LastEditorUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    uas.AvgPostScore,
    plv.VoteTypeId,
    plv.CreationDate,
    rpe.CreationDate,
    rpe.Comment,
    p.Body
HAVING COUNT(p.Id) > 0 OR SUM(COALESCE(p.Score, 0)) > 100
ORDER BY p.LastActivityDate DESC
LIMIT 1000;