WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RowNumByType,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScore,
        COUNT(ph.Id) AS PostHistoryCount,
        CASE
            WHEN p.Title IS NOT NULL AND CHAR_LENGTH(p.Title) > 50 THEN SUBSTRING(p.Title FROM 1 FOR 50) || '...'
            ELSE p.Title
        END AS ShortTitle,
        CASE
            WHEN p.Body IS NOT NULL AND CHAR_LENGTH(p.Body) > 200 THEN SUBSTRING(p.Body FROM 1 FOR 200) || '...'
            ELSE p.Body
        END AS ShortBody
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.CreationDate >= DATE '2023-01-01'
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.CommunityOwnedDate, pt.Name,
        p.Title, p.Body
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(rp.PostId) AS NumberOfPosts,
        AVG(rp.PostScore) AS AveragePostScore,
        SUM(rp.PostViewCount) AS TotalPostViews,
        MAX(rp.PostCreationDate) AS LastPostCreationDate,
        SUM(CASE WHEN rp.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN rp.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    JOIN RankedPosts rp ON u.Id = rp.OwnerUserId
    WHERE rp.RowNumByType <= 100
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
TopRatedUsers AS (
    SELECT
        UserId,
        UserDisplayName,
        Reputation,
        NumberOfPosts,
        AveragePostScore,
        TotalPostViews,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC, TotalPostViews DESC) AS UserRank
    FROM UserPostActivity
    WHERE Reputation > 1000 AND NumberOfPosts > 50
)
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.ShortTitle,
    rp.PostScore,
    rp.PostViewCount,
    rp.TotalCommentScore,
    rp.PostHistoryCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(tru.UserRank, 9999) AS OwnerRank,
    CASE
        WHEN rp.AnswerCount IS NULL OR rp.AnswerCount = 0 THEN 'No Answers'
        WHEN rp.AnswerCount > 0 AND rp.AnswerCount <= 5 THEN CAST(rp.AnswerCount AS VARCHAR) || ' Answers'
        ELSE 'Many Answers'
    END AS AnswerStatus,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN CHAR_LENGTH(COALESCE(rp.ShortBody, '')) < 100 THEN 'Short Body'
        WHEN CHAR_LENGTH(COALESCE(rp.ShortBody, '')) BETWEEN 100 AND 500 THEN 'Medium Body'
        ELSE 'Long Body'
    END AS BodyLengthCategory,
    pl.PostId AS LinkedPostId,
    lt.Name AS LinkType
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON rp.PostId = pl.PostId AND pl.LinkTypeId = 3
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN TopRatedUsers tru ON rp.OwnerUserId = tru.UserId
WHERE rp.RowNumByType <= 200
  AND (rp.PostScore > 0 OR rp.CommentCount > 10)
  AND rp.PostTypeName IN ('Question', 'Answer')
UNION
SELECT
    rp.PostId,
    rp.PostTypeName,
    rp.ShortTitle,
    rp.PostScore,
    rp.PostViewCount,
    rp.TotalCommentScore,
    rp.PostHistoryCount,
    rp.ClosedDate,
    rp.CommunityOwnedDate,
    COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
    u.Reputation AS OwnerReputation,
    COALESCE(tru.UserRank, 9999) AS OwnerRank,
    CASE
        WHEN rp.AnswerCount IS NULL OR rp.AnswerCount = 0 THEN 'No Answers'
        WHEN rp.AnswerCount > 0 AND rp.AnswerCount <= 5 THEN CAST(rp.AnswerCount AS VARCHAR) || ' Answers'
        ELSE 'Many Answers'
    END AS AnswerStatus,
    CASE
        WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN rp.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
        ELSE 'Open'
    END AS PostStatus,
    CASE
        WHEN CHAR_LENGTH(COALESCE(rp.ShortBody, '')) < 100 THEN 'Short Body'
        WHEN CHAR_LENGTH(COALESCE(rp.ShortBody, '')) BETWEEN 100 AND 500 THEN 'Medium Body'
        ELSE 'Long Body'
    END AS BodyLengthCategory,
    pl.PostId AS LinkedPostId,
    lt.Name AS LinkType
FROM RankedPosts rp
LEFT JOIN Users u ON rp.OwnerUserId = u.Id
LEFT JOIN PostLinks pl ON rp.PostId = pl.RelatedPostId AND pl.LinkTypeId = 3
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
LEFT JOIN TopRatedUsers tru ON rp.OwnerUserId = tru.UserId
WHERE rp.RowNumByType <= 200
  AND (rp.PostScore > 0 OR rp.CommentCount > 10)
  AND rp.PostTypeName IN ('Question', 'Answer')
ORDER BY OwnerRank, PostScore DESC
LIMIT 500;